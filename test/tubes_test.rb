# test/tubes_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Tubes do
  describe "for #find" do
    before do
      @beanstalk  = stub
      @tubes = Beaneater::Tubes.new(@beanstalk)
    end

    it("should return Tube obj") { assert_kind_of Beaneater::Tube, @tubes.find(:foo) }
    it("should return Tube name") { assert_equal "foo", @tubes.find(:foo).name }
    it("should support hash syntax") { assert_equal "bar", @tubes["bar"].name }
  end # find

  describe "for #use" do
    before do
      @beanstalk = Beaneater.new('localhost')
    end

    it "should switch to used tube for valid name" do
      tube = Beaneater::Tube.new(@beanstalk, 'some_name')
      @beanstalk.tubes.use('some_name')
      assert_equal 'some_name', @beanstalk.tubes.used.name
    end

    it "should raise for invalid tube name" do
      assert_raises(Beaneater::InvalidTubeName) { @beanstalk.tubes.use('; ') }
    end
  end # use

  describe "for #watch & #watched" do
    before do
      @beanstalk = Beaneater.new('localhost')
    end

    it 'should watch specified tubes' do
      @beanstalk.tubes.watch('foo')
      @beanstalk.tubes.watch('bar')
      assert_equal ['default', 'foo', 'bar'].sort, @beanstalk.tubes.watched.map(&:name).sort
    end

    it 'should raise invalid name for bad tube' do
      assert_raises(Beaneater::InvalidTubeName) { @beanstalk.tubes.watch('; ') }
    end
  end # watch! & watched

  describe "for #all" do
    before do
      @beanstalk = Beaneater.new('localhost')
      @beanstalk.tubes.find('foo').put 'bar'
      @beanstalk.tubes.find('bar').put 'foo'
    end

    it 'should retrieve all tubes' do
      ['default', 'foo', 'bar'].each do |t|
        assert @beanstalk.tubes.all.map(&:name).include?(t)
      end
    end
  end # all

  describe "for #used" do
    before do
      @beanstalk = Beaneater.new('localhost')
      @beanstalk.tubes.find('foo').put 'bar'
      @beanstalk.tubes.find('bar').put 'foo'
    end

    it 'should retrieve used tube' do
      assert_equal 'bar', @beanstalk.tubes.used.name
    end

    it 'should support dashed tubes' do
      @beanstalk.tubes.find('der-bam').put 'foo'
      assert_equal 'der-bam', @beanstalk.tubes.used.name
    end
  end # used

  describe "for #watch!" do
    before do
      @beanstalk = Beaneater.new('localhost')
    end

    it 'should watch specified tubes' do
      @beanstalk.tubes.watch!(:foo)
      @beanstalk.tubes.watch!('bar')
      assert_equal ['bar'].sort, @beanstalk.tubes.watched.map(&:name).sort
    end
  end # watch!

  describe "for #ignore" do
    before do
      @beanstalk = Beaneater.new('localhost')
    end

    it 'should ignore specified tubes' do
      @beanstalk.tubes.watch('foo')
      @beanstalk.tubes.watch('bar')
      @beanstalk.tubes.ignore('foo')
      assert_equal ['default', 'bar'].sort, @beanstalk.tubes.watched.map(&:name).sort
    end
  end # ignore

  describe "for #reserve" do
    before do
      @beanstalk  = Beaneater.new('localhost')
      @tube  = @beanstalk.tubes.find 'tube'
      @time = Time.now.to_i
      @tube.put "foo reserve #{@time}"
    end

    it("should reserve job") do
      @beanstalk.tubes.watch 'tube'
      job = @beanstalk.tubes.reserve
      assert_equal "foo reserve #{@time}", job.body
      job.delete
    end

    it("should reserve job with block") do
      @beanstalk.tubes.watch 'tube'
      job = nil
      @beanstalk.tubes.reserve { |j| job = j; job.delete }
      assert_equal "foo reserve #{@time}", job.body
    end

    it("should reserve job with block and timeout") do
      @beanstalk.tubes.watch 'tube'
      job = nil
      res = @beanstalk.tubes.reserve(0)  { |j| job = j; job.delete }
      assert_equal "foo reserve #{@time}", job.body
    end

    it "should raise TimedOutError with timeout" do
      @beanstalk.tubes.watch 'tube'
      @beanstalk.tubes.reserve(0)  { |j| job = j; job.delete }
      assert_raises(Beaneater::TimedOutError) { @beanstalk.tubes.reserve(0) }
    end

    it "should raise DeadlineSoonError with ttr 1" do
      @tube.reserve.delete
      @tube.put "foo reserve #{@time}", :ttr => 1
      @beanstalk.tubes.watch 'tube'
      @beanstalk.tubes.reserve
      assert_raises(Beaneater::DeadlineSoonError) { @beanstalk.tubes.reserve(0) }
    end

    after do
      cleanup_tubes!(['foo', 'tube'])
    end
  end # reserve
end # Beaneater::Tubes
