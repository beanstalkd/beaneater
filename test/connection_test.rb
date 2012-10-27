# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Connection do

  describe 'for #new' do
    before do
      @host = 'localhost'
      @bc = Beaneater::Connection.new(@host)
    end

    it "should init telnet connection" do
      telops = @bc.telnet_connection.instance_variable_get(:@options)
      assert_kind_of Net::Telnet, @bc.telnet_connection
      assert_equal 'localhost', telops["Host"]
      assert_equal 11300, telops["Port"]
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
      Net::Telnet.any_instance.expects(:cmd).with('String' => 'foo').returns('INSERTED 254')
      res = @bc.transmit 'foo'
      assert_equal '254', res[:id]
      assert_equal 'INSERTED', res[:status]
    end
  end # transmit
end # Beaneater::Connection