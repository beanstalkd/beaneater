# frozen_string_literal: true

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
      if @bc.connection.peeraddr[0] == 'AF_INET'
        assert_equal '127.0.0.1', @bc.connection.peeraddr[3]
      else
        assert_equal 'AF_INET6', @bc.connection.peeraddr[0]
        assert_equal '::1', @bc.connection.peeraddr[3]
      end
      assert_equal 11300, @bc.connection.peeraddr[1]
    end

    it "should raise on invalid connection" do
      assert_raises(Beaneater::NotConnected) { Beaneater::Connection.new("localhost:8544") }
    end

    it "should support array connection to single connection" do
      @bc2 = Beaneater::Connection.new([@host])
      assert_equal 'localhost', @bc.address
      assert_equal 'localhost', @bc.host
      assert_equal 11300, @bc.port
    end
  end # new

  describe 'for timeout configuration' do
    after do
      Beaneater.configure do |config|
        config.connect_timeout = nil
        config.resolv_timeout  = nil
        config.read_timeout    = nil
        config.write_timeout   = nil
      end
    end

    it "should pass connect_timeout and resolv_timeout to TCPSocket.new on Ruby >= 3.0" do
      skip("connect_timeout/resolv_timeout kwargs require Ruby >= 3.0") if RUBY_VERSION < "3.0"

      Beaneater.configure do |config|
        config.connect_timeout = 2
        config.resolv_timeout  = 2
      end

      real_socket = TCPSocket.new('localhost', 11300)
      TCPSocket.expects(:new).with('localhost', 11300, connect_timeout: 2, resolv_timeout: 2).returns(real_socket)

      bc = Beaneater::Connection.new('localhost')
      assert_kind_of TCPSocket, bc.connection
    end

    it "should ignore connect_timeout and resolv_timeout on Ruby < 3.0" do
      skip("connect_timeout/resolv_timeout kwargs are supported on Ruby >= 3.0") if RUBY_VERSION >= "3.0"

      Beaneater.configure do |config|
        config.connect_timeout = 2
        config.resolv_timeout  = 4
      end

      real_socket = TCPSocket.new('localhost', 11300)
      TCPSocket.expects(:new).with('localhost', 11300).returns(real_socket)

      bc = Beaneater::Connection.new('localhost')
      assert_same real_socket, bc.connection
    end

    it "should set SO_RCVTIMEO and SO_SNDTIMEO when read/write timeouts are configured" do
      Beaneater.configure do |config|
        config.read_timeout  = 3
        config.write_timeout = 5
      end

      bc = Beaneater::Connection.new('localhost')
      rcv = bc.connection.getsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO).unpack('l_l_')[0]
      snd = bc.connection.getsockopt(Socket::SOL_SOCKET, Socket::SO_SNDTIMEO).unpack('l_l_')[0]
      assert_equal 3, rcv
      assert_equal 5, snd
    end

  end # timeout configuration

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

    it "should keep the types of stats values without mangling them" do
      @bc.transmit "use stats-tube.1"
      id = @bc.transmit("put 0 0 100 1\r\nX")[:id]
      tube = @bc.transmit('stats-tube stats-tube.1')[:body]
      assert_equal 'stats-tube.1', tube['name']
      assert_equal 1, tube['current-jobs-ready']

      stats = @bc.transmit('stats')[:body]
      assert_kind_of Integer, stats['current-connections']
      assert_kind_of Float, stats['rusage-utime']
      assert_kind_of String, stats['version']
      assert_kind_of String, stats['hostname']
      assert_equal false, stats['draining']
    ensure
      @bc.transmit "delete #{id}" if id
      @bc.transmit "use default"
    end

    it "should return id" do
      res = @bc.transmit "put 0 0 100 1\r\nX"
      assert res[:id]
      assert_equal 'INSERTED', res[:status]
    end

    it "should support dashes in response" do
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

    it "should retry command with success after one connection failure" do
      TCPSocket.any_instance.expects(:readline).times(2).
        raises(EOFError.new).then.
        returns("DELETED 56\nFOO")

      res = @bc.transmit "delete 56\r\n"
      assert_equal 'DELETED', res[:status]
    end

    it "should fail after exceeding retries with DrainingError" do
      TCPSocket.any_instance.expects(:readline).times(3).
        raises(Beaneater::UnexpectedResponse.from_status("DRAINING", "delete 56"))

      assert_raises(Beaneater::DrainingError) { @bc.transmit "delete 56\r\n" }
    end

    it "should fail after exceeding reconnect max retries" do
      # next connection attempts should fail
      TCPSocket.stubs(:new).times(3).raises(Errno::ECONNREFUSED.new)
      TCPSocket.any_instance.stubs(:readline).times(1).raises(EOFError.new)

      assert_raises(Beaneater::NotConnected) { @bc.transmit "delete 56\r\n" }
    end

    it "tubes_watched are restored after reconnect" do
      client = Beaneater.new('127.0.0.1:11300')
      client.tubes.watch! "another"

      $called = false
      TCPSocket.prepend Module.new {
        def readline
          if !$called
            $called = true
            raise EOFError
          end

          super
        end
      }

      assert_equal %w[another], client.tubes.watched.map(&:name)
    ensure
      $called = nil
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
