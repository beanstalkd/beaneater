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

    it "should init connection" do
      assert_kind_of TCPSocket, @bc.connection
      assert_equal '127.0.0.1', @bc.connection.peeraddr[3]
      assert_equal 11300, @bc.connection.peeraddr[1]
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
#      TCPSocket.any_instance.expects(:write).with("foo\r\n").returns('INSERTED 254')
      res = @bc.transmit "put 0 0 100 1\r\nX"
      assert res[:id]
      assert_equal 'INSERTED', res[:status]
    end

    it "should support dashes in response" do
#      TCPSocket.any_instance.expects(:write).with("bar\r\n").returns('USING foo-bar')
      res = @bc.transmit "use foo-bar\r\n"
      assert_equal 'USING', res[:status]
      assert_equal 'foo-bar', res[:id]
    end

    it "should pass crlf through without changing its length" do
      res = @bc.transmit "put 0 0 100 2\r\n\r\n"
      assert_equal 'INSERTED', res[:status]
    end

    it "should handle *any* byte value without changing length" do
      res = @bc.transmit "put 0 0 100 256\r\n"+(0..255).to_a.pack("c*")
      assert_equal 'INSERTED', res[:status]
    end
  end # transmit

  describe 'for #close' do
    before do
      @host = 'localhost'
      @bc = Beaneater::Connection.new(@host)
    end

    it "should clear connection" do
      assert_kind_of TCPSocket, @bc.connection
      @bc.close
      assert_nil @bc.connection
      assert_raises(Beaneater::NotConnected) { @bc.transmit 'stats' }
    end
  end # close
end # Beaneater::Connection
