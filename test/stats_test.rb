# frozen_string_literal: true

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

  describe 'for #respond_to?' do
    before do
      connection = stub(:transmit => { :body => { 'max-job-size' => 65535 }, :status => "OK" })
      @stats = Beaneater::Stats.new(stub(:connection => connection))
    end

    it "should respond to a stats key before it is first read" do
      assert @stats.respond_to?(:max_job_size), "Expected stats to respond to max_job_size"
      assert_equal 65535, @stats.method(:max_job_size).call
    end

    it "should not respond to a name that is not a stats key" do
      refute @stats.respond_to?(:no_such_stat)
    end
  end # respond_to?
end # Beaneater::Stats
