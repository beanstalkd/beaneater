# test/connection_test.rb

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
      @tube.put "bar #{@time}"
      assert_equal "bar #{@time}", @tube.peek(:ready).body
    end

    it "should insert a delayed job" do
      @tube.put "delayed #{@time}", :delay => 1
      assert_equal "delayed #{@time}", @tube.peek(:delayed).body
    end
  end #find

  describe "for #peek" do
    before do
      @time = Time.now.to_i
    end

    it "should peek delayed" do
      @tube.put "foo #{@time}", :delay => 2
      assert_equal "foo #{@time}", @tube.peek(:delayed).body
    end

    it "should peek ready" do
      @tube.put "foo #{@time}", :delay => 0
      assert_equal "foo #{@time}", @tube.peek(:ready).body
    end

    # it "should peek buried" do
    #   TODO add bury test
    # end
  end

  describe "for #reserve" do
    before do
      @time = Time.now.to_i
      @tube.put "foo #{@time}", :delay => 0
    end

    it "should reserve job" do
      assert_equal "foo #{@time}", @tube.reserve.body
    end

    it "should reserve job with block" do
      job = nil
      @tube.reserve { |j| job = j }
      assert_equal "foo #{@time}", job.body
    end
  end # reserve

  describe "for #stats" do
    before do
      @time = Time.now.to_i
      @tube.put "foo #{@time}"
      @stats = @tube.stats
    end

    it "should return total number of jobs in tube" do
      assert_equal 1, @stats['current_jobs_ready']
      assert_equal 0, @stats['current_jobs_delayed']
    end
  end # stats

  after do
    cleanup_tubes!(['baz', 'jaz'])
  end
end # Beaneater::Tubes