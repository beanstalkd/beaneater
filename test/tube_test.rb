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
      @tube.put "bar put #{@time}"
      assert_equal "bar put #{@time}", @tube.peek(:ready).body
    end

    it "should insert a delayed job" do
      @tube.put "delayed put #{@time}", :delay => 1
      assert_equal "delayed put #{@time}", @tube.peek(:delayed).body
    end

    it "should try to put 2 times before put successfully" do
      Beaneater::Tubes.any_instance.expects(:use).once
      Beaneater::Connection.any_instance.expects(:transmit).times(2).
        raises(Beaneater::DrainingError.new(nil, nil)).then.returns('foo')
      assert_equal 'foo', @tube.put("bar put #{@time}")
    end

    it "should try to put 3 times before to raise" do
      Beaneater::Tubes.any_instance.expects(:use).once
      Beaneater::Connection.any_instance.expects(:transmit).times(3).raises(Beaneater::DrainingError.new(nil, nil))
      assert_raises(Beaneater::DrainingError) { @tube.put "bar put #{@time}" }
    end

    after do
      Beaneater::Connection.any_instance.unstub(:transmit)
    end
  end # put

  describe "for #peek" do
    before do
      @time = Time.now.to_i
    end

    it "should peek delayed" do
      @tube.put "foo delay #{@time}", :delay => 1
      assert_equal "foo delay #{@time}", @tube.peek(:delayed).body
    end

    it "should peek ready" do
      @tube.put "foo ready #{@time}", :delay => 0
      assert_equal "foo ready #{@time}", @tube.peek(:ready).body
    end

    it "should peek buried" do
      @tube.put "foo buried #{@time}"
      @tube.reserve.bury

      assert_equal "foo buried #{@time}", @tube.peek(:buried).body
    end

    it "should return nil for empty peek" do
      assert_nil @tube.peek(:buried)
    end
  end # peek

  describe "for #reserve" do
    before do
      @time = Time.now.to_i
      @tube.put "foo reserve #{@time}"
    end

    it "should reserve job" do
      assert_equal "foo reserve #{@time}", @tube.reserve.body
    end

    it "should reserve job with block" do
      job = nil
      @tube.reserve { |j| job = j; job.delete }
      assert_equal "foo reserve #{@time}", job.body
    end
  end # reserve

  describe "for #pause" do
    before do
      @time = Time.now.to_i
      @tube = Beaneater::Tube.new(@pool, 'bam')
      @tube.put "foo pause #{@time}"
    end

    it "should allow tube pause" do
      assert_equal 0, @tube.stats.pause
      @tube.pause(1)
      assert_equal 1, @tube.stats.pause
    end
  end # pause

  describe "for #stats" do
    before do
      @time = Time.now.to_i
      @tube.put "foo stats #{@time}"
      @stats = @tube.stats
    end

    it "should return total number of jobs in tube" do
      assert_equal 1, @stats['current_jobs_ready']
      assert_equal 0, @stats.current_jobs_delayed
    end

    it "should raise error for empty tube" do
      assert_raises(Beaneater::NotFoundError) { @pool.tubes.find('fake_tube').stats }
    end
  end # stats

  after do
    cleanup_tubes!(['baz'])
  end
end # Beaneater::Tubes