# frozen_string_literal: true

# test/tube_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Tube do
  before do
    @beanstalk = Beaneater.new('localhost')
    @tube = Beaneater::Tube.new(@beanstalk, 'baz')
  end

  describe "for #put" do
    before do
      @time = Time.now.to_i
    end

    it "should insert a job" do
      @tube.put "bar put #{@time}"
      assert_equal "bar put #{@time}", @tube.peek(:ready).body
      assert_equal 120, @tube.peek(:ready).ttr
      assert_equal 65536, @tube.peek(:ready).pri
      assert_equal 0, @tube.peek(:ready).delay
    end

    it "should insert a delayed job" do
      @tube.put "delayed put #{@time}", :delay => 1
      assert_equal "delayed put #{@time}", @tube.peek(:delayed).body
    end

    it "should support custom serializer" do
      Beaneater.configure.job_serializer = lambda { |b| JSON.dump(b) }
      @tube.put({ foo: "bar"})
      assert_equal '{"foo":"bar"}', @tube.peek(:ready).body
    end

    after do
      Beaneater::Connection.any_instance.unstub(:transmit)
      Beaneater.configure.job_serializer = lambda { |b| b }
    end
  end # put

  describe "for #peek" do
    before do
      @time = Time.now.to_i
    end

    it "should peek delayed" do
      @tube.put "foo delay #{@time}", :delay => 1
      assert_equal "foo delay #{@time}", @tube.peek(:delayed).body
    end

    it "should peek ready" do
      @tube.put "foo ready #{@time}", :delay => 0
      assert_equal "foo ready #{@time}", @tube.peek(:ready).body
    end

    it "should peek buried" do
      @tube.put "foo buried #{@time}"
      @tube.reserve.bury

      assert_equal "foo buried #{@time}", @tube.peek(:buried).body
    end

    it "should return nil for empty peek" do
      assert_nil @tube.peek(:buried)
    end

    it "supports valid JSON" do
      json = '{ "foo" : "bar" }'
      @tube.put(json)
      assert_equal 'bar', JSON.parse(@tube.peek(:ready).body)['foo']
    end

    it "supports non valid JSON" do
      json = '{"message":"hi"}'
      @tube.put(json)
      assert_equal 'hi', JSON.parse(@tube.peek(:ready).body)['message']
    end

    it "supports passing crlf through" do
      @tube.put("\r\n")
      assert_equal "\r\n", @tube.peek(:ready).body
    end

    it "supports passing any byte value through" do
      bytes = (0..255).to_a.pack("c*")
      @tube.put(bytes)
      assert_equal bytes, @tube.peek(:ready).body
    end

    it "should support custom parser" do
      Beaneater.configure.job_parser = lambda { |b| JSON.parse(b) }
      json = '{"message": "hi: there! this: is a long message"}'
      @tube.put(json)
      assert_equal 'hi: there! this: is a long message', @tube.peek(:ready).body['message']
    end

    it "should keep the connection usable when the custom parser raises" do
      Beaneater.configure.job_parser = lambda { |b| JSON.parse(b) }
      @tube.put('not json')
      socket = @beanstalk.connection.connection
      assert_raises(JSON::ParserError) { @tube.peek(:ready) }
      assert_same socket, @beanstalk.connection.connection
      assert_equal 'baz', @beanstalk.tubes.used.name
    end

    after do
      Beaneater.configure.job_parser = lambda { |b| b }
    end
  end # peek

  describe "for a job_parser that raises on reserve" do
    before do
      Beaneater.configure.job_parser = lambda { |b| JSON.parse(b) }
      @tube = @beanstalk.tubes.find('poison_tube')
      @poison_id = @tube.put('not json', :pri => 1)[:id]
      @tube.put('{"ok":1}', :pri => 2)
      @beanstalk.tubes.watch!('poison_tube')
    end

    after do
      Beaneater.configure.job_parser = lambda { |b| b }
      # The bad job is still reserved by this connection, which clearing the tube can't touch;
      # left alone, it would be released when the socket is collected, into a later test.
      begin
        @beanstalk.connection.transmit("delete #{@poison_id}")
      rescue Beaneater::NotFoundError
        nil
      end
      cleanup_tubes!(['poison_tube'])
    end

    it "should raise the parser's own error from reserve, tagged with the job id" do
      error = assert_raises(JSON::ParserError) { @beanstalk.tubes.reserve(0) }
      assert_kind_of Beaneater::JobParseFailure, error
      assert_equal @poison_id, error.job_id
      assert_nil error.cause # the parser's error had none
      Beaneater.configure.job_parser = lambda { |b| b }
      assert_equal 'reserved', @beanstalk.connection.transmit("stats-job #{error.job_id}")[:body]['state']
    end

    it "should keep the parser's error intact: class, message, backtrace and cause" do
      original = nil
      Beaneater.configure.job_parser = lambda do |b|
        begin
          JSON.parse(b)
        rescue JSON::ParserError => ex
          original = ex
          raise ArgumentError, 'not a job' # its cause is the ParserError
        end
      end
      error = assert_raises(ArgumentError) { @beanstalk.tubes.reserve(0) }
      assert_equal @poison_id, error.job_id
      assert_equal 'not a job', error.message
      assert_same original, error.cause
      assert_operator error.backtrace.first, :include?, 'tube_test.rb'
      refute_nil error.backtrace_locations
    end

    it "should not tag an exception the parser reuses, so a later error carries no old id" do
      shared = JSON::ParserError.new('always this one')
      Beaneater.configure.job_parser = lambda { |b| raise shared }
      error = assert_raises(JSON::ParserError) { @beanstalk.tubes.reserve(0) }
      assert_equal @poison_id, error.job_id
      peeked = assert_raises(JSON::ParserError) { @tube.peek(:ready) } # not a reserve: not tagged
      refute_kind_of Beaneater::JobParseFailure, peeked
      refute_kind_of Beaneater::JobParseFailure, shared
    end

    it "should keep the connection, so the bad job stays reserved and the next job is delivered" do
      socket = @beanstalk.connection.connection
      assert_raises(JSON::ParserError) { @beanstalk.tubes.reserve(0) }
      assert_same socket, @beanstalk.connection.connection
      job = @beanstalk.tubes.reserve(0)
      assert_equal({ 'ok' => 1 }, job.body)
      job.delete
    end

    it "should keep the connection when the raising parser used the same client first" do
      tube = 'poison_tube'
      Beaneater.configure.job_parser = lambda { |b| @beanstalk.connection.transmit("use #{tube}"); JSON.parse(b) }
      socket = @beanstalk.connection.connection
      assert_raises(JSON::ParserError) { @beanstalk.tubes.reserve(0) }
      assert_same socket, @beanstalk.connection.connection
      job = @beanstalk.tubes.reserve(0)
      assert_equal({ 'ok' => 1 }, job.body)
      job.delete
    end
  end # job_parser that raises on reserve

  describe "for #reserve" do
    before do
      @time = Time.now.to_i
      @json = %Q&{ "foo" : "#{@time} bar" }&
      @tube.put @json
    end

    it "should reserve job" do
      @job = @tube.reserve
      assert_equal "#{@time} bar", JSON.parse(@job.body)['foo']
      @job.delete
    end

    it "should reserve job with block" do
      job = nil
      @tube.reserve { |j| job = j; job.delete }
      assert_equal "#{@time} bar", JSON.parse(job.body)['foo']
    end

    it "should support custom parser" do
      Beaneater.configure.job_parser = lambda { |b| JSON.parse(b) }
      @job = @tube.reserve
      assert_equal "#{@time} bar", @job.body['foo']
      @job.delete
    end

    after do
      Beaneater.configure.job_parser = lambda { |b| b }
    end
  end # reserve

  describe "for #pause" do
    before do
      @time = Time.now.to_i
      @tube = Beaneater::Tube.new(@beanstalk, 'bam')
      @tube.put "foo pause #{@time}"
    end

    it "should allow tube pause" do
      assert_equal 0, @tube.stats.pause
      @tube.pause(1)
      assert_equal 1, @tube.stats.pause
    end
  end # pause

  describe "for #stats" do
    before do
      @time = Time.now.to_i
      @tube.put "foo stats #{@time}"
      @stats = @tube.stats
    end

    it "should return total number of jobs in tube" do
      assert_equal 1, @stats['current_jobs_ready']
      assert_equal 0, @stats.current_jobs_delayed
    end

    it "should raise error for empty tube" do
      assert_raises(Beaneater::NotFoundError) { @beanstalk.tubes.find('fake_tube').stats }
    end
  end # stats

  describe "for #kick" do
    before do
      @time, @time2 = 2.times.map { Time.now.to_i }
      @tube.put "kick #{@time}"
      @tube.put "kick #{@time2}"

      2.times.map { @tube.reserve.bury }
    end

    it "should kick 2 buried jobs" do
      assert_equal 2, @tube.stats.current_jobs_buried
      @tube.kick(2)
      assert_equal 0, @tube.stats.current_jobs_buried
      assert_equal 2, @tube.stats.current_jobs_ready
    end
  end # kick

  describe "for #clear" do
    @time = Time.now.to_i
    before do
      2.times { |i| @tube.put "to clear success #{i} #{@time}" }
      2.times { |i| @tube.put "to clear delayed #{i} #{@time}", :delay => 5 }
      2.times { |i| @tube.put "to clear bury #{i} #{@time}", :pri => 1 }
      @tube.reserve.bury while @tube.peek(:ready).stats['pri'] == 1
    end

    it "should clear all jobs in tube" do
      tube_counts = lambda { %w(ready buried delayed).map { |s| @tube.stats["current_jobs_#{s}"] } }
      assert_equal [2, 2, 2], tube_counts.call
      @tube.clear
      @tube.stats
      assert_equal [0, 0, 0], tube_counts.call
    end
  end # clear
end # Beaneater::Tube
