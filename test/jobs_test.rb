# frozen_string_literal: true

# test/jobs_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Jobs do
  before do
    @beanstalk = Beaneater.new('localhost')
    @jobs = Beaneater::Jobs.new(@beanstalk)
    @tube = @beanstalk.tubes.find('baz')
  end

  describe "for #find" do
    before do
      @time = Time.now.to_i
      @tube.put("foo find #{@time}")
      @job = @tube.peek(:ready)
    end

    it "should return job from id" do
      assert_equal "foo find #{@time}", @jobs.find(@job.id).body
    end

    it "should return job using peek" do
      assert_equal "foo find #{@time}", @jobs.find(@job.id).body
    end

    it "should return job using hash syntax" do
      assert_equal "foo find #{@time}", @jobs.find(@job.id).body
    end

    it "should return nil for invalid negative id" do
      assert_nil @jobs.find(10000) 
    end

    it "should return nil for invalid negative id" do
      assert_raises(Beaneater::BadFormatError) { @jobs.find(-1) }
    end
  end # find

  describe "for #register!" do
    before do
      $foo = 0
      @jobs.register('tube', :retry_on => [Timeout::Error]) do |job|
        $foo += 1
      end
    end

    it "should store processor" do
      assert_equal 'tube', @jobs.processors.keys.first
      assert_equal [Timeout::Error], @jobs.processors.values.first[:retry_on]
    end

    it "should store block for 'tube'" do
      @jobs.processors['tube'][:block].call nil
      assert_equal 1, $foo
    end
  end # register!

  describe "for process!" do
    before do
      $foo = []

      @jobs.register('tube_success', :retry_on => [Timeout::Error]) do |job|
        # p job.body
        $foo << job.body
        raise Beaneater::AbortProcessingError if job.body =~ /abort/
      end

      @jobs.register('tube_release', :retry_on => [Timeout::Error], :max_retries => 2) do |job|
        $foo << job.body
        raise Timeout::Error
      end

      @jobs.register('tube_buried') do |job|
        $foo << job.body
        raise RuntimeError
      end

      cleanup_tubes!(['tube_success', 'tube_release', 'tube_buried'])

      @beanstalk.tubes.find('tube_success').put("success abort", :pri => 2**31 + 1)
      @beanstalk.tubes.find('tube_success').put("success 2", :pri => 1)
      @beanstalk.tubes.find('tube_release').put("released")
      @beanstalk.tubes.find('tube_buried').put("buried")

      @jobs.process!(:release_delay => 0)
    end

    it "should process all jobs" do
      assert_equal ['success 2', 'released', 'released', 'released', 'buried', 'success abort'], $foo
    end

    it "should clear successful_jobs" do
      assert_equal 0, @beanstalk.tubes.find('tube_success').stats.current_jobs_ready
      assert_equal 1, @beanstalk.tubes.find('tube_success').stats.current_jobs_buried
      assert_equal 0, @beanstalk.tubes.find('tube_success').stats.current_jobs_reserved
    end

    it "should retry release jobs 2 times" do
      assert_equal 2, @beanstalk.tubes.find('tube_release').peek(:buried).stats.releases
    end

    it "should bury unexpected exception" do
      assert_equal 1, @beanstalk.tubes.find('tube_buried').stats.current_jobs_buried
    end
  end # for_process!

  describe "for process! with a dashed tube name" do
    before do
      $ran = []
      cleanup_tubes!(['email-jobs', 'tube_stop'])
      @jobs.register('email-jobs') { |job| $ran << job.body }
      @jobs.register('tube_stop') { |job| $ran << job.body; @jobs.stop! }
      @beanstalk.tubes.find('email-jobs').put('email', :pri => 1)
      @beanstalk.tubes.find('tube_stop').put('stop', :pri => 2)
      @jobs.process!(:release_delay => 0)
    end

    it "should run the handler registered for the tube" do
      assert_equal ['email', 'stop'], $ran
      assert_nil @beanstalk.tubes.find('email-jobs').peek(:buried)
    end
  end # process! with a dashed tube name

  describe "for process! when a failing handler no longer holds its job" do
    before do
      $foo = []
      cleanup_tubes!(['tube_lost'])
    end

    after do
      cleanup_tubes!(['tube_lost'])
    end

    # The handler loses 'first', puts 'second' and raises. 'second' outranks 'first', so it is
    # reserved next whatever happened to 'first'.
    def process_until_second_job(ttr = 120, &lose_job)
      tube = @beanstalk.tubes.find('tube_lost')
      @jobs.register('tube_lost') do |job|
        $foo << job.body
        if job.body == 'second'
          @jobs.stop!
        else
          lose_job.call(job)
          tube.put('second', :pri => 0)
          raise RuntimeError
        end
      end
      tube.put('first', :pri => 1, :ttr => ttr)
      Timeout.timeout(15) { @jobs.process!(:reserve_timeout => 1) }
    end

    it "keeps processing when the handler deleted the job" do
      process_until_second_job { |job| job.delete }
      assert_equal ['first', 'second'], $foo
    end

    it "keeps processing when the handler released the job" do
      process_until_second_job { |job| job.release(:delay => 5) }
      assert_equal ['first', 'second'], $foo
      assert_equal 1, @beanstalk.tubes.find('tube_lost').stats.current_jobs_delayed
    end

    it "keeps processing when the handler overran the job's TTR" do
      process_until_second_job(1) do |job|
        # the server releases a job some time after its TTR runs out
        deadline = Time.now + 10
        sleep 0.1 while job.stats.state == 'reserved' && Time.now < deadline
        refute_equal 'reserved', job.stats.state
      end
      assert_equal ['first', 'second'], $foo
    end
  end

  describe "for process! when the server goes away" do
    before do
      @port = free_port
      @pid = start_beanstalkd(@port)
      @client = Beaneater.new("127.0.0.1:#{@port}")
    end

    after do
      @client.close if @client
      stop_beanstalkd(@pid) if @pid
    end

    it "raises NotConnected instead of looping, and the client resumes once the server is back" do
      seen = []
      @client.jobs.register('reconnect') do |job|
        seen << job.body
        @client.jobs.stop! if job.body == 'after restart'
      end
      @client.tubes.find('reconnect').put('before outage')

      worker = Thread.new do
        begin
          @client.jobs.process!(:reserve_timeout => 1)
        rescue StandardError => ex
          ex
        end
      end
      Timeout.timeout(5) { sleep 0.05 while seen.empty? }
      stop_beanstalkd(@pid)

      finished = worker.join(10)
      worker.kill unless finished
      assert finished, "process! was still running 10s after the server went away"
      assert_kind_of Beaneater::NotConnected, worker.value

      @pid = start_beanstalkd(@port)
      producer = Beaneater.new("127.0.0.1:#{@port}")
      producer.tubes.find('reconnect').put('after restart')
      producer.close

      Timeout.timeout(10) { @client.jobs.process!(:reserve_timeout => 1) }
      assert_equal ['before outage', 'after restart'], seen
    end
  end
end # Beaneater::Jobs
