# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Job do
  before do
    @pool  = Beaneater::Pool.new(['localhost'])
    @tube  = @pool.tubes.find 'tube'
  end

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

    after do
      cleanup_tubes!(['tube'])
    end
  end # delete

  describe "for #stats" do
    before do
      @tube.put 'foo'
      @job = @tube.peek(:ready)
    end

    it("should have stats") do
      assert_equal 'tube', @job.stats['tube']
      assert_equal 'ready', @job.stats.state
    end

    after do
      cleanup_tubes!(['tube'])
    end
  end # stats
end # Beaneater::Tubes