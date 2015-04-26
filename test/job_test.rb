# test/job_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Job do
  before do
    @beanstalk  = Beaneater.new('localhost')
    @tube  = @beanstalk.tubes.find 'tube'
  end

  describe "for #bury" do
    before do
      @time = Time.now.to_i
      @tube.put "foo bury #{@time}", :pri => 5
    end

    it("should be buried with same pri") do
      job = @tube.reserve
      assert_equal "foo bury #{@time}", job.body
      assert_equal 'reserved', job.stats.state
      job.bury
      assert_equal 'buried', job.stats.state
      assert_equal 5, job.stats.pri
      assert_equal "foo bury #{@time}", @tube.peek(:buried).body
    end

    it("should be released with new pri") do
      job = @tube.reserve
      assert_equal "foo bury #{@time}", job.body
      assert_equal 'reserved', job.stats.state
      job.bury(:pri => 10)
      assert_equal 'buried', job.stats.state
      assert_equal 10, job.stats.pri
      assert_equal "foo bury #{@time}", @tube.peek(:buried).body
    end

    it "should not bury if not reserved" do
      job = @tube.peek(:ready)
      assert_raises(Beaneater::JobNotReserved) { job.bury }
    end

    it "should not bury if reserved and deleted" do
      job = @tube.reserve
      job.delete
      assert_equal false, job.reserved
      assert_raises(Beaneater::NotFoundError) { job.bury }
    end
  end # bury

  describe "for #release" do
    before do
      @time = Time.now.to_i
      @tube.put "foo release #{@time}", :pri => 5
    end

    it("should be released with same pri") do
      job = @tube.reserve
      assert_equal "foo release #{@time}", job.body
      assert_equal 'reserved', job.stats.state
      job.release
      assert_equal 'ready', job.stats.state
      assert_equal 5, job.stats.pri
      assert_equal 0, job.stats.delay
    end

    it("should be released with new pri") do
      job = @tube.reserve
      assert_equal "foo release #{@time}", job.body
      assert_equal 'reserved', job.stats.state
      job.release :pri => 10, :delay => 2
      assert_equal 'delayed', job.stats.state
      assert_equal 10, job.stats.pri
      assert_equal 2, job.stats.delay
    end

    it "should not released if not reserved" do
      job = @tube.peek(:ready)
      assert_raises(Beaneater::JobNotReserved) { job.release }
    end

    it "should not release if not reserved and buried" do
      job = @tube.reserve
      job.bury
      assert_raises(Beaneater::JobNotReserved) { job.release }
    end
  end # release

  describe "for #delete" do
    before do
      @tube.put 'foo'
    end

    it("should deletable") do
      job = @tube.peek(:ready)
      assert_equal 'foo', job.body
      job.delete
      assert_nil @tube.peek(:ready)
    end
  end # delete

  describe "for #touch" do
    before do
      @tube.put 'foo touch', :ttr => 1
    end

    it("should be toucheable") do
      job = @tube.reserve
      assert_equal 'foo touch', job.body
      job.touch
      assert_equal 1, job.stats.reserves
      job.delete
    end

    it "should not touch if not reserved" do
      job = @tube.peek(:ready)
      assert_raises(Beaneater::JobNotReserved) { job.touch }
    end

    it "should not touch if not reserved and released" do
      job = @tube.reserve
      job.release
      assert_raises(Beaneater::JobNotReserved) { job.touch }
    end

    it "should not touch if reserved and deleted" do
      job = @tube.reserve
      job.delete
      assert_raises(Beaneater::NotFoundError) { job.touch }
    end
  end # touch

  describe "for #kick" do
    before do
      @tube.put 'foo touch', :ttr => 1
    end

    it("should be toucheable") do
      job = @tube.reserve
      assert_equal 'foo touch', job.body
      job.bury
      assert_equal 1, @tube.stats.current_jobs_buried
      if @beanstalk.stats.version.to_f > 1.7
        job.kick
        assert_equal 0, @tube.stats.current_jobs_buried
        assert_equal 1, @tube.stats.current_jobs_ready
      end
    end
  end # kick

  describe "for #stats" do
    before do
      @tube.put 'foo'
      @job = @tube.peek(:ready)
    end

    it("should have stats") do
      assert_equal 'tube', @job.stats['tube']
      assert_equal 'ready', @job.stats.state
    end

    it "should return nil for deleted job with no stats" do
      @job.delete
      assert_raises(Beaneater::NotFoundError) { @job.stats }
    end
  end # stats

  describe "for #reserved?" do
    before do
      @tube.put 'foo'
      @job = @tube.peek(:ready)
    end

    it("should have stats") do
      assert_equal false, @job.reserved?
      job = @tube.reserve
      assert_equal job.id, @job.id
      assert_equal true, @job.reserved?
      @job.delete
      assert_raises(Beaneater::NotFoundError) { @job.reserved? }
    end
  end # reserved?

  describe "for #exists?" do
    before do
      @tube.put 'foo'
      @job = @tube.peek(:ready)
    end

    it("should exists") { assert @job.exists? }

    it "should not exist" do
      @job.delete
      assert !@job.exists?
    end
  end # exists?

  describe "for #tube" do
    before do
      @tube.put 'bar'
      @job = @tube.peek(:ready)
    end

    it("should have stats") do
      job = @tube.reserve
      assert_equal @tube.name, job.tube
      job.release
    end
  end # tube

  describe "for #pri" do
    before do
      @tube.put 'bar', :pri => 1
      @job = @tube.peek(:ready)
    end

    it("should return pri") do
      job = @tube.reserve
      assert_equal 1, job.pri
      job.release
    end
  end # pri


  describe "for #ttr" do
    before do
      @tube.put 'bar', :ttr => 5
      @job = @tube.peek(:ready)
    end

    it("should return ttr") do
      job = @tube.reserve
      assert_equal 5, job.ttr
      job.release
    end
  end # ttr

  describe "for #delay" do
    before do
      @tube.put 'bar', :delay => 5
      @job = @tube.peek(:delayed)
    end

    it("should return delay") do
      assert_equal 5, @job.delay
    end
  end # delay
end # Beaneater::Job
