# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Job do
  describe "for #delete" do
    before do
      @pool  = Beaneater::Pool.new(['localhost'])
      @tube  = @pool.tubes.find 'tube'
      @tube.put 'foo'
    end

    it("should deletable") do
      job = @tube.peek(:ready)
      assert_equal 'foo', job.body

      job.delete
      assert_nil @tube.peek(:ready)
    end

    after do
      cleanup_tubes!(['tube']) if @tube.peek(:ready)
    end
  end # delete
end # Beaneater::Tubes