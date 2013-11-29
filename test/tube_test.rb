# test/tube_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Tube do
  before do
    @pool = Beaneater::Pool.new(['localhost'])
    @tube = Beaneater::Tube.new(@pool, 'baz')
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

    it "should try to put 2 times before put successfully" do
      Beaneater::Connection.any_instance.expects(:transmit).once.with(includes('use baz'), {})
      Beaneater::Connection.any_instance.expects(:transmit).times(2).with(includes("bar put #{@time}"), {}).
        raises(Beaneater::DrainingError.new(nil, nil)).then.returns('foo')
      assert_equal 'foo', @tube.put("bar put #{@time}")
    end

    it "should try to put 3 times before to raise" do
      Beaneater::Connection.any_instance.expects(:transmit).once.with(includes('use baz'), {})
      Beaneater::Connection.any_instance.expects(:transmit).with(includes("bar put #{@time}"), {}).
        times(3).raises(Beaneater::DrainingError.new(nil, nil))
      assert_raises(Beaneater::DrainingError) { @tube.put "bar put #{@time}" }
    end

    after do
      Beaneater::Connection.any_instance.unstub(:transmit)
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
      json = '{"message":"hi"}'
      @tube.put(json)
      assert_equal 'hi', @tube.peek(:ready).body['message']
    end

    after do
      Beaneater.configure.job_parser = lambda { |b| b }
    end
  end # peek

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
      @tube = Beaneater::Tube.new(@pool, 'bam')
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
      assert_raises(Beaneater::NotFoundError) { @pool.tubes.find('fake_tube').stats }
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
      stats = @tube.stats
      assert_equal [0, 0, 0], tube_counts.call
    end
  end # clear

  after do
    cleanup_tubes!(['baz'])
  end
end # Beaneater::Tube
