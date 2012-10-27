# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Tubes do
  describe "for #find" do
    before do
      @pool  =  stub
      @tubes = Beaneater::Tubes.new(@pool)
    end

    it("should return Tube obj") { assert_kind_of Beaneater::Tube, @tubes.find(:foo) }
    it("should return Tube name") { assert_equal :foo, @tubes.find(:foo).name }
  end #find

  describe "for #watch & #watched" do
    before do
      @pool = Beaneater::Pool.new(['localhost'])
    end

    it 'should watch specified tubes' do
      @pool.tubes.watch('foo')
      @pool.tubes.watch('bar')
      assert_equal ['default', 'foo', 'bar'].sort, @pool.tubes.watched.sort
    end
  end

  describe "for #watch!" do
    before do
      @pool = Beaneater::Pool.new(['localhost'])
    end

    it 'should watch specified tubes' do
      @pool.tubes.watch!(:foo)
      @pool.tubes.watch!('bar')
      assert_equal ['bar'].sort, @pool.tubes.watched.sort
    end
  end

  describe "for #ignore!" do
    before do
      @pool = Beaneater::Pool.new(['localhost'])
    end

    it 'should ignore specified tubes' do
      @pool.tubes.watch('foo')
      @pool.tubes.watch('bar')
      @pool.tubes.ignore!('foo')
      assert_equal ['default', 'bar'].sort, @pool.tubes.watched.sort
    end
  end

  describe "for #reserve" do
    before do
      @pool  = Beaneater::Pool.new(['localhost'])
      @tube  = @pool.tubes.find 'tube'
      @tube.put 'foo'
    end

    it("should reserve job") do
      @pool.tubes.watch 'tube'
      job = @pool.tubes.reserve
      assert_equal 'foo', job.body
      job.delete
    end

    it("should reserve job with block") do
      @pool.tubes.watch 'tube'
      job = nil
      @pool.tubes.reserve { |j| job = j; job.delete }
      assert_equal 'foo', job.body
    end

    after do
      cleanup_tubes!(['foo', 'tube'])
    end
  end # reserve
end # Beaneater::Tubes