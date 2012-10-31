# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Job do
  before do
    @pool  = Beaneater::Pool.new(['localhost'])
    @tube  = @pool.tubes.find 'tube'
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
  end # touch

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

  after do
    cleanup_tubes!(['tube'])
  end
end # Beaneater::Tubes