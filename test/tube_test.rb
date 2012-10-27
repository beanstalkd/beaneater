# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Tube do
  describe "for #put" do
    before do
      @pool = Beaneater::Pool.new(['localhost'])
      @tube = Beaneater::Tube.new(@pool, 'baz')
    end

    it "should insert a job" do
      @tube.put "bar"
      assert_equal "bar", @tube.peek(:ready).body
    end

    it "should insert a delayed job" do
      @tube.put "delayed", :delay => 1
      assert_equal "delayed", @tube.peek(:delayed).body
    end
  end #find

  describe "for #peek" do
    before do
      @pool = Beaneater::Pool.new(['localhost'])
      @tube = Beaneater::Tube.new(@pool, 'baz')
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

  after do
    cleanup_tubes!(['baz']) if @tube.peek(:ready) || @tube.peek(:delayed)
  end
end # Beaneater::Tubes