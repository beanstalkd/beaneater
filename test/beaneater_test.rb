require File.expand_path('../test_helper', __FILE__)

describe "beanstalk-client" do
  before do
    @beanstalk = Beaneater::Pool.new(['127.0.0.1:11300'])
    @tubes = ['one', 'two', 'three']

    # Put something on each tube so they exist
    tube_one = @beanstalk.tubes.find('one')
    tube_one.put('one')

    tube_two = @beanstalk.tubes.find('two')
    tube_two.put('two')
  end

  describe "test thread safe one" do
    before do
      # Create threads that will execute
      # A: use one
      # B: use one
      # B: put two
      # A: put one
      a = Thread.new do
        tube_one = @beanstalk.tubes.find('one')
        sleep 4
        tube_one.put('one')
      end

      b = Thread.new do
        sleep 1
        tube_two = @beanstalk.tubes.find('two')
        tube_two.put('two')
      end

      a.join
      b.join
    end

    it "should return correct current-jobs-ready for tube one" do
      one = @beanstalk.tubes.find('one').stats
      assert_equal 2, one.current_jobs_ready
    end

    it "should return correct current-jobs-ready for tube two" do
      two = @beanstalk.tubes.find('two').stats
      assert_equal 2, two.current_jobs_ready
    end
  end

  describe "test thread safe two" do
    before do
      a = Thread.new do
        tube_one = @beanstalk.tubes.find('one')
        sleep 4
        tube_one.put('one')
      end

      b = Thread.new do
        tube_two = @beanstalk.tubes.find('two')
        sleep 1
        tube_two.put('two')
      end

      a.join
      b.join
    end

    it "should return correct current-jobs-ready for tube one" do
      one = @beanstalk.tubes.find('one').stats
      assert_equal 2, one.current_jobs_ready
    end

    it "should return correct current-jobs-ready for tube two" do
      two = @beanstalk.tubes.find('two').stats
      assert_equal 2, two.current_jobs_ready
    end
  end

  describe "test delete job in reserved state" do
    before do
      @tube_three = @beanstalk.tubes.find('three')
      @tube_three.put('one')
      @job = @tube_three.reserve
    end

    it "should be deleted properly" do
      assert_equal 'one', @job.body
      assert_equal 'one', @beanstalk.jobs.find(@job.id).body
      @job.delete
      assert_nil @beanstalk.jobs.find(@job.id)
    end
  end

  describe "test delete job in buried state" do
    before do
      @tube_three = @beanstalk.tubes.find('three')
      @tube_three.put('two')
      @job = @tube_three.reserve
    end

    it "should delete job as expected in buried state" do
      assert_equal 'two', @job.body
      @job.bury
      assert_equal 'two', @tube_three.peek(:buried).body

      @job.delete
      assert_nil @beanstalk.jobs.find(@job.id)
    end
  end

  after do
    cleanup_tubes!(@tubes, @beanstalk)
  end

end
