# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Connection do

  describe 'for #new' do
    before do
      @host = 'localhost'
      @bc = Beaneater::Connection.new(@host)
    end

    it "should store address, host and port" do
      assert_equal 'localhost', @bc.address
      assert_equal 'localhost', @bc.host
      assert_equal 11300, @bc.port
    end

    it "should init telnet connection" do
      telops = @bc.telnet_connection.instance_variable_get(:@options)
      assert_kind_of Net::Telnet, @bc.telnet_connection
      assert_equal 'localhost', telops["Host"]
      assert_equal 11300, telops["Port"]
    end

    it "should raise on invalid connection" do
      assert_raises(Beaneater::NotConnected) { Beaneater::Connection.new("localhost:8544") }
    end
  end # new

  describe 'for #transmit' do
    before do
      @host = 'localhost'
      @bc = Beaneater::Connection.new(@host)
    end

    it "should return yaml loaded response" do
      res = @bc.transmit 'stats'
      refute_nil res[:body]['current-connections']
      assert_equal 'OK', res[:status]
    end

    it "should return id" do
      Net::Telnet.any_instance.expects(:cmd).with(has_entries('String' => 'foo')).returns('INSERTED 254')
      res = @bc.transmit 'foo'
      assert_equal '254', res[:id]
      assert_equal 'INSERTED', res[:status]
    end

    it "should support dashes in response" do
      Net::Telnet.any_instance.expects(:cmd).with(has_entries('String' => 'bar')).returns('USING foo-bar')
      res = @bc.transmit 'bar'
      assert_equal 'USING', res[:status]
      assert_equal 'foo-bar', res[:id]
    end
  end # transmit

  describe 'for #close' do
    before do
      @host = 'localhost'
      @bc = Beaneater::Connection.new(@host)
    end

    it "should clear telnet connection" do
      assert_kind_of Net::Telnet, @bc.telnet_connection
      @bc.close
      assert_nil @bc.telnet_connection
      assert_raises(Beaneater::NotConnected) { @bc.transmit 'stats' }
    end
  end # close
end # Beaneater::Connection