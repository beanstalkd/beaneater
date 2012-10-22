# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Connection do

  describe 'for #new' do
    before do
      @addr_string_port = 'localhost:11301'
      @addr_num_port = '127.0.0.1:11302'
      @addr_string = 'host.local'
      @addr_num = '1.1.1.1:11303'
      @addresses = [@addr_string_port, @addr_num_port, @addr_string, @addr_num]

      Net::Telnet.expects(:new).with('Host' => 'localhost', 'Port' => 11301).once
      Net::Telnet.expects(:new).with('Host' => '127.0.0.1', 'Port' => 11302).once
      Net::Telnet.expects(:new).with('Host' => 'host.local', 'Port' => 11300).once
      Net::Telnet.expects(:new).with('Host' => '1.1.1.1', 'Port' => 11303).once

      @bc = Beaneater::Connection.new(@addresses)
    end

    it "should init 4 telnet connections" do
      assert_equal 4, @bc.telnet_connections.size
    end
  end
end