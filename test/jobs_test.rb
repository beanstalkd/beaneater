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

  after do
    cleanup_tubes!(['baz'])
  end
end