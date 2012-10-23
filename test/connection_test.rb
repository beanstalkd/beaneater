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

      Net::Telnet.expects(:new).with('Host' => 'localhost', "Port" => 11301, "Prompt" => /\n\n/).once
      Net::Telnet.expects(:new).with('Host' => '127.0.0.1', "Port" => 11302, "Prompt" => /\n\n/).once
      Net::Telnet.expects(:new).with('Host' => 'host.local', "Port" => 11300, "Prompt" => /\n\n/).once
      Net::Telnet.expects(:new).with('Host' => '1.1.1.1', "Port" => 11303, "Prompt" => /\n\n/).once

      @bc = Beaneater::Connection.new(@hosts)
    end

    it "should init 4 telnet connections" do
      assert_equal 4, @bc.telnet_connections.size
    end
  end
end