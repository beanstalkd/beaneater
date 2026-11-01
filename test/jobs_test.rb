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

  describe "for process! with no processors" do
    it "should raise ArgumentError without sending a command" do
      client = Beaneater.new('localhost') # not @beanstalk, which the teardown uses
      client.connection.expects(:transmit).never
      error = assert_raises(ArgumentError) { Beaneater::Jobs.new(client).process! }
      assert_match(/register/, error.message)
    ensure
      client.close if client
    end
  end # process! with no processors

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

  describe "for process! with stop!" do
    before do
      cleanup_tubes!(['tube_stop'])
    end

    after do
      cleanup_tubes!(['tube_stop'])
    end

    # Runs process! in a thread and yields. Returns :returned, the exception process! raised, or
    # :still_running if it hadn't finished within seconds.
    def process_in_thread(seconds)
      worker = Thread.new do
        begin
          @jobs.process!(:reserve_timeout => 1)
          :returned
        rescue StandardError => ex
          ex
        end
      end
      yield if block_given?
      return worker.value if worker.join(seconds)
      worker.kill
      :still_running
    end

    it "returns within one reserve_timeout when stop! is called while idle" do
      @jobs.register('tube_stop') { |job| }
      result = process_in_thread(3) do
        sleep 0.5
        @jobs.stop!
      end
      assert_equal :returned, result
    end

    it "returns when stop! is called by a handler whose job another worker took over" do
      other = Beaneater.new('localhost')
      other.tubes.watch!('tube_stop')
      runs = 0
      @jobs.register('tube_stop') do |job|
        runs += 1
        job.release # as the server does once a job's TTR runs out
        other.tubes.reserve(1)
        @jobs.stop!
      end
      @beanstalk.tubes.find('tube_stop').put('taken over')

      assert_equal :returned, process_in_thread(5)
      assert_equal 1, runs
    ensure
      other.close if other
    end
  end

  describe "for process! when the job_parser rejects a job" do
    before do
      cleanup_tubes!(['tube_bad_body'])
      Beaneater.configure.job_parser = lambda { |body| JSON.parse(body) }
    end

    after do
      Beaneater.configure.job_parser = lambda { |body| body }
      cleanup_tubes!(['tube_bad_body'])
    end

    it "buries the job and goes on to the next one" do
      handled = []
      @jobs.register('tube_bad_body') do |job|
        handled << job.body
        @jobs.stop!
      end
      tube = @beanstalk.tubes.find('tube_bad_body')
      tube.put('not json', :pri => 1)
      tube.put('{"ok":1}', :pri => 2)

      Timeout.timeout(10) { @jobs.process!(:reserve_timeout => 1) }
      assert_equal [{ 'ok' => 1 }], handled
      Beaneater.configure.job_parser = lambda { |body| body }
      buried = tube.peek(:buried)
      refute_nil buried, "the job the parser rejected was not buried"
      assert_equal 'not json', buried.body
    end

    # process! goes on after NotFoundError (and JobNotReserved, TimedOutError); the job it had
    # must not be taken for the bad job that follows.
    def put_after_retry_jobs
      tube = @beanstalk.tubes.find('tube_bad_body')
      first = tube.put('{"first":1}', :pri => 1)[:id]
      bad = tube.put('not json', :pri => 2)[:id]
      tube.put('{"stop":1}', :pri => 3)
      [tube, first, bad]
    end

    def stats_of(id)
      Beaneater.configure.job_parser = lambda { |body| body }
      @beanstalk.connection.transmit("stats-job #{id}")[:body]
    end

    it "buries the bad job after a handler deleted its own job" do
      @jobs.register('tube_bad_body') do |job|
        job.body == { 'stop' => 1 } ? @jobs.stop! : job.delete # process!'s own delete then gets NOT_FOUND
      end
      tube, _first, bad = put_after_retry_jobs
      Timeout.timeout(10) { @jobs.process!(:reserve_timeout => 1) }
      assert_equal 'buried', stats_of(bad)['state']
    end

    it "buries both the failed job and the bad job after a handler raised NotFoundError" do
      @jobs.register('tube_bad_body') do |job|
        if job.body == { 'stop' => 1 }
          @jobs.stop!
        else
          @beanstalk.connection.transmit('delete 999999') # NOT_FOUND for some other job
        end
      end
      tube, first, bad = put_after_retry_jobs
      Timeout.timeout(10) { @jobs.process!(:reserve_timeout => 1) }
      assert_equal 'buried', stats_of(bad)['state']
      assert_equal 'buried', stats_of(first)['state'] # its handler failed, with the job still reserved
    ensure
      begin
        @beanstalk.connection.transmit("delete #{first}") if first
      rescue Beaneater::NotFoundError
        nil
      end
    end

    it "buries the job when the parser raises an error process! handles itself" do
      Beaneater.configure.job_parser = lambda do |body|
        raise Beaneater::NotFoundError.new('NOT_FOUND', 'parse') if body == 'not found'
        raise Beaneater::TimedOutError.new('TIMED_OUT', 'parse') if body == 'timed out'
        body
      end
      handled = []
      @jobs.register('tube_bad_body') do |job|
        handled << job.body
        @jobs.stop!
      end
      tube = @beanstalk.tubes.find('tube_bad_body')
      not_found = tube.put('not found', :pri => 1, :ttr => 2)[:id]
      timed_out = tube.put('timed out', :pri => 2, :ttr => 2)[:id]
      tube.put('stop', :pri => 3)

      Timeout.timeout(10) { @jobs.process!(:reserve_timeout => 1) }
      assert_equal ['stop'], handled
      [not_found, timed_out].each do |id|
        stats = stats_of(id)
        assert_equal 'buried', stats['state'], "job #{id}"
        assert_equal 0, stats['timeouts'], "job #{id}"
      end
    end

    it "buries the job and stops when the parser raises AbortProcessingError" do
      Beaneater.configure.job_parser = lambda { |body| raise Beaneater::AbortProcessingError if body == 'abort'; body }
      @jobs.register('tube_bad_body') { |job| }
      id = @beanstalk.tubes.find('tube_bad_body').put('abort')[:id]
      Timeout.timeout(10) { @jobs.process!(:reserve_timeout => 1) }
      assert_equal 'buried', stats_of(id)['state']
    end

    it "buries the job when the parser raises a frozen exception" do
      frozen = ArgumentError.new('frozen').freeze
      Beaneater.configure.job_parser = lambda { |body| body == 'bad' ? raise(frozen) : body }
      handled = []
      @jobs.register('tube_bad_body') do |job|
        handled << job.body
        @jobs.stop!
      end
      tube = @beanstalk.tubes.find('tube_bad_body')
      tube.put('bad', :pri => 1)
      tube.put('good', :pri => 2)

      Timeout.timeout(10) { @jobs.process!(:reserve_timeout => 1) }
      assert_equal ['good'], handled
      Beaneater.configure.job_parser = lambda { |body| body }
      assert_equal 'bad', (tube.peek(:buried) || flunk("the bad job was not buried")).body
    end

    it "buries the handler's job, not the one its own reserve rejected, when a handler raises it" do
      cleanup_tubes!(['tube_bad_body_other'])
      other_id = @beanstalk.tubes.find('tube_bad_body_other').put('not json')[:id]
      @jobs.register('tube_bad_body') do |job|
        @jobs.stop!
        @beanstalk.tubes.watch('tube_bad_body_other')
        @beanstalk.tubes.reserve(0) # raises: the parser rejects the other tube's job
      end
      @beanstalk.tubes.find('tube_bad_body').put('{"ok":1}')

      Timeout.timeout(10) { @jobs.process!(:reserve_timeout => 1) }
      Beaneater.configure.job_parser = lambda { |body| body }
      assert_equal '{"ok":1}', (@beanstalk.tubes.find('tube_bad_body').peek(:buried) || flunk("the handler's job was not buried")).body
      assert_equal 'reserved', @beanstalk.connection.transmit("stats-job #{other_id}")[:body]['state']
    ensure
      Beaneater.configure.job_parser = lambda { |body| body }
      begin
        @beanstalk.connection.transmit("delete #{other_id}") if other_id
      rescue Beaneater::NotFoundError
        nil
      end
      cleanup_tubes!(['tube_bad_body_other'])
    end
  end

  describe "for process! when a handler raises NotFoundError with its job reserved" do
    before do
      cleanup_tubes!(['tube_not_found'])
    end

    after do
      cleanup_tubes!(['tube_not_found'])
    end

    it "buries the job once instead of reserving in a loop near its TTR" do
      runs = 0
      @jobs.register('tube_not_found') do |job|
        runs += 1
        @beanstalk.connection.transmit('delete 999999') # NOT_FOUND for some other job
      end
      id = @beanstalk.tubes.find('tube_not_found').put('x', :ttr => 2)[:id]
      worker = Thread.new { @jobs.process!(:reserve_timeout => 1) }
      sleep 3 # past the job's TTR
      @jobs.stop!
      assert worker.join(5), "process! did not stop"
      checker = Beaneater.new('localhost')
      stats = checker.connection.transmit("stats-job #{id}")[:body]
      checker.close
      assert_equal 1, runs
      assert_equal 'buried', stats['state']
      assert_equal 0, stats['timeouts']
    end

    it "goes on when the job stops being reserved just before it is buried" do
      @jobs.register('tube_not_found') do |job|
        @jobs.stop!
        raise 'handler failed'
      end
      id = @beanstalk.tubes.find('tube_not_found').put('x')[:id]
      Beaneater::Job.any_instance.stubs(:bury).raises(Beaneater::JobNotReserved) # another client's reservation ended
      Timeout.timeout(10) { @jobs.process!(:reserve_timeout => 1) } # must not raise JobNotReserved
      assert_nil @jobs.current_job
    ensure
      Beaneater::Job.any_instance.unstub(:bury)
      begin
        @beanstalk.connection.transmit("delete #{id}") if id
      rescue Beaneater::NotFoundError
        nil
      end
    end

    it "releases the job for another try instead when the error is in retry_on" do
      runs = 0
      @jobs.register('tube_not_found', :retry_on => [Beaneater::NotFoundError], :max_retries => 1) do |job|
        runs += 1
        @jobs.stop! if runs == 2
        @beanstalk.connection.transmit('delete 999999') # NOT_FOUND for some other job
      end
      id = @beanstalk.tubes.find('tube_not_found').put('x')[:id]
      Timeout.timeout(10) { @jobs.process!(:reserve_timeout => 1, :release_delay => 0) }
      stats = @beanstalk.connection.transmit("stats-job #{id}")[:body]
      assert_equal 2, runs
      assert_equal 1, stats['releases'] # released once, then buried once the retries ran out
      assert_equal 'buried', stats['state']
    end
  end

  describe "for process! when a handler raises NotConnected for another server" do
    before do
      cleanup_tubes!(['tube_other_down'])
    end

    it "buries the job and keeps processing" do
      seen = []
      @jobs.register('tube_other_down') do |job|
        seen << job.body
        @jobs.stop! if job.body == 'second'
        raise Beaneater::NotConnected, "the other server is down" if job.body == 'first'
      end
      tube = @beanstalk.tubes.find('tube_other_down')
      tube.put('first', :pri => 1)
      tube.put('second', :pri => 2)

      Timeout.timeout(10) { @jobs.process!(:reserve_timeout => 1) }
      assert_equal ['first', 'second'], seen
      assert_equal 'first', tube.peek(:buried).body
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

    it "forgets the job when burying it fails, so the next run buries its own bad job" do
      Beaneater.configure.job_parser = lambda do |body|
        stop_beanstalkd(@pid) if body == 'kill' # the server dies before the bad job is buried
        JSON.parse(body)
      end
      handled = []
      @client.jobs.register('bury_fails') do |job|
        handled << job.body
        @client.jobs.stop!
      end
      @client.tubes.find('bury_fails').put('kill')
      assert_raises(Beaneater::NotConnected) { Timeout.timeout(10) { @client.jobs.process!(:reserve_timeout => 1) } }
      assert_nil @client.jobs.current_job

      @pid = start_beanstalkd(@port) # a new server: job ids start again at 1
      producer = Beaneater.new("127.0.0.1:#{@port}")
      producer.tubes.find('bury_fails_filler').put('filler') # takes the id the lost job had
      producer.tubes.find('bury_fails').put('not json', :pri => 1)
      producer.tubes.find('bury_fails').put('{"ok":1}', :pri => 2)
      Timeout.timeout(10) { @client.jobs.process!(:reserve_timeout => 1) }
      assert_equal [{ 'ok' => 1 }], handled
      Beaneater.configure.job_parser = lambda { |body| body }
      buried = producer.tubes.find('bury_fails').peek(:buried)
      refute_nil buried, "the bad job was not buried"
      assert_equal 'not json', buried.body
      producer.close
    ensure
      Beaneater.configure.job_parser = lambda { |body| body }
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
