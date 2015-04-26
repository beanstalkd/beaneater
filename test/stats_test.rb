# test/stats_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Stats do
  before do
    connection = stub(:transmit => { :body => { 'uptime' => 1, 'cmd-use' => 2 }, :status => "OK"})
    @beanstalk = stub(:connection => connection)
    @stats = Beaneater::Stats.new(@beanstalk)
  end

  describe 'for #[]' do
    it "should return stats by key" do
      assert_equal 1, @stats[:uptime]
    end

    it "should return stats by underscore key" do
      assert_equal 2, @stats[:'cmd_use']
    end
  end # []

  describe 'for #keys' do
    it "should return list of keys" do
      assert_equal 2, @stats.keys.size
      assert @stats.keys.include?('uptime'), "Expected keys to include 'uptime'"
      assert @stats.keys.include?('cmd_use'), "Expected keys to include 'cmd-use'"
    end
  end # keys

  describe 'for #method_missing' do
    it "should return stats by key" do
      assert_equal 1, @stats.uptime
    end

    it "should return stats by underscore key" do
      assert_equal 2, @stats.cmd_use
    end

    it "should raise NoMethodError" do
      assert_raises(NoMethodError) { @stats.cmd }
    end
  end # method_missing
end # Beaneater::Stats
