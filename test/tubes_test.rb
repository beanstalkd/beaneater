# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Tubes do
  describe "for #find" do
    before do
      @pool  = stub
      @tubes = Beaneater::Tubes.new(@pool)
    end

    it("should return Tube obj") { assert_kind_of Beaneater::Tube, @tubes.find(:foo) }
    it("should return Tube name") { assert_equal "foo", @tubes.find(:foo).name }
    it("should support hash syntax") { assert_equal "bar", @tubes["bar"].name }
  end # find

  describe "for #use" do
    before do
      @pool = Beaneater::Pool.new(['localhost'])
    end

    it "should switch to used tube for valid name" do
      tube = Beaneater::Tube.new(@pool, 'some_name')
      @pool.tubes.use('some_name')
      assert_equal 'some_name', @pool.tubes.used.name
    end

    it "should raise for invalid tube name" do
      assert_raises(Beaneater::InvalidTubeName) { @pool.tubes.use('; ') }
    end
  end # use

  describe "for #watch & #watched" do
    before do
      @pool = Beaneater::Pool.new(['localhost'])
    end

    it 'should watch specified tubes' do
      @pool.tubes.watch('foo')
      @pool.tubes.watch('bar')
      assert_equal ['default', 'foo', 'bar'].sort, @pool.tubes.watched.map(&:name).sort
    end

    it 'should raise invalid name for bad tube' do
      assert_raises(Beaneater::InvalidTubeName) { @pool.tubes.watch('; ') }
    end
  end # watch! & watched

  describe "for #all" do
    before do
      @pool = Beaneater::Pool.new(['localhost'])
      @pool.tubes.find('foo').put 'bar'
      @pool.tubes.find('bar').put 'foo'
    end

    it 'should retrieve all tubes' do
      ['default', 'foo', 'bar'].each do |t|
        assert @pool.tubes.all.map(&:name).include?(t)
      end
    end
  end # all

  describe "for #used" do
    before do
      @pool = Beaneater::Pool.new(['localhost'])
      @pool.tubes.find('foo').put 'bar'
      @pool.tubes.find('bar').put 'foo'
    end

    it 'should retrieve used tube' do
      assert_equal 'bar', @pool.tubes.used.name
    end

    it 'should support dashed tubes' do
      @pool.tubes.find('der-bam').put 'foo'
      assert_equal 'der-bam', @pool.tubes.used.name
    end
  end # used

  describe "for #watch!" do
    before do
      @pool = Beaneater::Pool.new(['localhost'])
    end

    it 'should watch specified tubes' do
      @pool.tubes.watch!(:foo)
      @pool.tubes.watch!('bar')
      assert_equal ['bar'].sort, @pool.tubes.watched.map(&:name).sort
    end
  end # watch!

  describe "for #ignore" do
    before do
      @pool = Beaneater::Pool.new(['localhost'])
    end

    it 'should ignore specified tubes' do
      @pool.tubes.watch('foo')
      @pool.tubes.watch('bar')
      @pool.tubes.ignore('foo')
      assert_equal ['default', 'bar'].sort, @pool.tubes.watched.map(&:name).sort
    end
  end # ignore

  describe "for #reserve" do
    before do
      @pool  = Beaneater::Pool.new(['localhost'])
      @tube  = @pool.tubes.find 'tube'
      @time = Time.now.to_i
      @tube.put "foo reserve #{@time}"
    end

    it("should reserve job") do
      @pool.tubes.watch 'tube'
      job = @pool.tubes.reserve
      assert_equal "foo reserve #{@time}", job.body
      job.delete
    end

    it("should reserve job with block") do
      @pool.tubes.watch 'tube'
      job = nil
      @pool.tubes.reserve { |j| job = j; job.delete }
      assert_equal "foo reserve #{@time}", job.body
    end

    it("should reserve job with block and timeout") do
      @pool.tubes.watch 'tube'
      job = nil
      res = @pool.tubes.reserve(0)  { |j| job = j; job.delete }
      assert_equal "foo reserve #{@time}", job.body
    end

    it "should raise TimedOutError with timeout" do
      @pool.tubes.watch 'tube'
      @pool.tubes.reserve(0)  { |j| job = j; job.delete }
      assert_raises(Beaneater::TimedOutError) { @pool.tubes.reserve(0) }
    end

    it "should raise TimedOutError no delete, with timeout" do
      @pool.tubes.watch 'tube'
      @pool.tubes.reserve(0)  { |j| job = j; job.delete }
      assert_raises(Beaneater::TimedOutError) { @pool.tubes.reserve(0) }
    end

    it "should raise DeadlineSoonError with ttr 1" do
      @tube.reserve.delete
      @tube.put "foo reserve #{@time}", :ttr => 1
      @pool.tubes.watch 'tube'
      @pool.tubes.reserve
      assert_raises(Beaneater::DeadlineSoonError) { @pool.tubes.reserve(0) }
    end

    after do
      cleanup_tubes!(['foo', 'tube'])
    end
  end # reserve
end # Beaneater::Tubes