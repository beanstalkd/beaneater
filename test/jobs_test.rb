# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Jobs do
  before do
    @pool = Beaneater::Pool.new(['localhost'])
    @jobs = Beaneater::Jobs.new(@pool)
    @tube = @pool.tubes.find('baz')
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

    it "should return nil for invalid id" do
      assert_nil @jobs.find(-1)
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

      @pool.tubes.find('tube_success').put("success abort", :pri => 2**31 + 1)
      @pool.tubes.find('tube_success').put("success 2", :pri => 1)
      @pool.tubes.find('tube_release').put("released")
      @pool.tubes.find('tube_buried').put("buried")

      @jobs.process!(:release_delay => 0)
    end

    it "should process all jobs" do
      assert_equal ['success 2', 'released', 'released', 'released', 'buried', 'success abort'], $foo
    end

    it "should clear successful_jobs" do
      assert_equal 0, @pool.tubes.find('tube_success').stats.current_jobs_ready
      assert_equal 1, @pool.tubes.find('tube_success').stats.current_jobs_buried
      assert_equal 0, @pool.tubes.find('tube_success').stats.current_jobs_reserved
    end

    it "should retry release jobs 2 times" do
      assert_equal 2, @pool.tubes.find('tube_release').peek(:buried).stats.releases
    end

    it "should bury unexpected exception" do
      assert_equal 1, @pool.tubes.find('tube_buried').stats.current_jobs_buried
    end
  end

  after do
    cleanup_tubes!(['baz', 'tube_success', 'tube_release', 'tube_buried'])
  end
end