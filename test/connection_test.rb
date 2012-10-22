# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Connection do

  describe 'for #new' do
    before do
      @host_string_port = 'localhost:11301'
      @host_num_port = '127.0.0.1:11302'
      @host_string = 'host.local'
      @host_num = '1.1.1.1:11303'
      @hosts = [@host_string_port, @host_num_port, @host_string, @host_num]

      TCPSocket.expects(:new).with('localhost', 11301).once
      TCPSocket.expects(:new).with('127.0.0.1', 11302).once
      TCPSocket.expects(:new).with('host.local', 11300).once
      TCPSocket.expects(:new).with('1.1.1.1', 11303).once

      @bc = Beaneater::Connection.new(@hosts)
    end

    it "should init 4 telnet connections" do
      assert_equal 4, @bc.sockets.size
    end
  end
end