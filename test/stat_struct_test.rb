# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::StatStruct do
  before do
    @hash = { :foo => "bar", :bar => "baz", :baz => "foo", :"under-score" => "demo" }
    @struct = Beaneater::StatStruct.from_hash(@hash)
  end

  describe "for #from_hash" do
    it "should have 4 keys" do
      assert_equal 'bar', @struct.foo
      assert_equal 'baz', @struct.bar
      assert_equal 'foo', @struct.baz
      assert_equal 'demo', @struct.under_score
    end
  end # from_hash

  describe "for [] access" do
    it "should have hash lookup" do
      assert_equal 'bar', @struct['foo']
      assert_equal 'baz', @struct['bar']
    end

    it "should convert keys to string" do
      assert_equal 'foo', @struct[:baz]
      assert_equal 'demo', @struct[:"under_score"]
    end
  end # []

  describe "for #keys" do
    it "should return 4 keys" do
      assert_equal 4, @struct.keys.size
    end

    it "should return expected keys" do
      assert_equal ['foo', 'bar', 'baz', 'under_score'].sort, @struct.keys.sort
    end
  end # keys
end