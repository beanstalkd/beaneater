# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Stats do
  before do
    @conn =  stub(:cmd => [{ :body => { 'x' => 1, 'y-z' => 2 }}, {:body => { 'x' => 3,'y-z' => 4 }}])
    @stats = Beaneater::Stats.new(@conn)
  end

  describe 'for #[]' do
    it "should return stats by key" do
      assert_equal 4, @stats[:x]
    end

    it "should return stats by underscore key" do
      assert_equal 6, @stats[:'y_z']
    end
  end #[]

  describe 'for #keys' do
    it "should return list of keys" do
      assert_equal ['x', 'y_z'].sort, @stats.keys.sort
    end
  end #keys

  describe 'for #method_missing' do
    it "should return stats by key" do
      assert_equal 4, @stats.x
    end

    it "should return stats by underscore key" do
      assert_equal 6, @stats.y_z
    end
  end #method_missing
end # Beaneater::Stats