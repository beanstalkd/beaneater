# frozen_string_literal: true

# test/stat_struct_test.rb

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

    it "should look up hyphenated beanstalkd keys" do
      assert_equal 'demo', @struct['under-score']
      assert_equal 'demo', @struct[:"under-score"]
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

  describe "for #respond_to?" do
    it "should respond to a key before it is first read" do
      struct = Beaneater::StatStruct.from_hash('rusage-utime' => 0.5)
      assert struct.respond_to?(:rusage_utime), "Expected struct to respond to rusage_utime"
      assert_equal 0.5, struct.method(:rusage_utime).call
    end

    it "should not respond to a name that is not a key" do
      refute @struct.respond_to?(:no_such_key)
    end
  end # respond_to?

  describe "for #to_h" do
    it "should return 4 keys / values" do
      assert_equal 4, @struct.to_h.size
    end

    it "should return expect hash" do
      assert_equal [['foo', 'bar'], ['bar', 'baz'], ['baz', 'foo'], ['under_score', 'demo']].sort, @struct.to_h.sort
    end
  end # to_h
end # Beaneater::StatStruct
