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

    # A server that accepts connections and then neither reads nor replies.
    def with_silent_server
      server = TCPServer.new('127.0.0.1', 0)
      clients = []
      acceptor = Thread.new { loop { clients << server.accept } }
      yield "127.0.0.1:#{server.addr[1]}", clients
    ensure
      acceptor.kill if acceptor
      clients.each(&:close)
      server.close if server
    end

    def elapsed
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end

    it "should raise SocketTimeout and drop the connection when no reply arrives within read_timeout" do
      Beaneater.configure { |config| config.read_timeout = 0.5 }
      with_silent_server do |address, clients|
        bc = Beaneater::Connection.new(address)
        time = elapsed do
          assert_raises(Beaneater::SocketTimeout) { Timeout.timeout(5) { bc.transmit('stats') } }
        end
        assert_in_delta 0.5, time, 0.4
        assert_nil bc.connection
        # the next command opens a new connection rather than reading the late reply
        assert_raises(Beaneater::SocketTimeout) { Timeout.timeout(5) { bc.transmit('stats') } }
        assert_equal 2, clients.size
      end
    end

    it "should raise SocketTimeout when a command cannot be written within write_timeout" do
      Beaneater.configure { |config| config.write_timeout = 0.5 }
      with_silent_server do |address|
        bc = Beaneater::Connection.new(address)
        body = 'x' * (64 * 1024 * 1024) # more than the socket buffers hold
        time = elapsed do
          assert_raises(Beaneater::SocketTimeout) do
            Timeout.timeout(5) { bc.transmit("put 0 0 100 #{body.bytesize}\r\n#{body}") }
          end
        end
        assert_operator time, :<, 2
        assert_nil bc.connection
      end
    end

    it "should wait reserve-with-timeout's own timeout on top of read_timeout" do
      Beaneater.configure { |config| config.read_timeout = 0.5 }
      client = Beaneater.new('localhost')
      client.tubes.watch!('read_timeout_empty')
      time = elapsed do
        assert_raises(Beaneater::TimedOutError) { client.tubes.reserve(1) }
      end
      assert_operator time, :>=, 0.9
      assert client.connection.connection, "connection should stay open"
      client.close
    end

    it "should not cut off a plain reserve with read_timeout" do
      Beaneater.configure { |config| config.read_timeout = 0.5 }
      client = Beaneater.new('localhost')
      client.tubes.watch!('read_timeout_reserve')
      producer = Thread.new do
        sleep 1
        Beaneater.new('localhost').tubes['read_timeout_reserve'].put('late')
      end
      job = nil
      time = elapsed { job = Timeout.timeout(5) { client.tubes.reserve } }
      assert_equal 'late', job.body
      assert_operator time, :>=, 0.9
      job.delete
      producer.join
      client.close
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
      TCPSocket.any_instance.expects(:readpartial).times(2).
        raises(EOFError.new).then.
        returns("DELETED 56\r\n")

      res = @bc.transmit "delete 56\r\n"
      assert_equal 'DELETED', res[:status]
    end

    it "should fail after exceeding retries with DrainingError" do
      TCPSocket.any_instance.expects(:readpartial).times(3).
        raises(Beaneater::UnexpectedResponse.from_status("DRAINING", "delete 56"))

      assert_raises(Beaneater::DrainingError) { @bc.transmit "delete 56\r\n" }
    end

    it "should fail after exceeding reconnect max retries" do
      # next connection attempts should fail
      TCPSocket.stubs(:new).times(3).raises(Errno::ECONNREFUSED.new)
      TCPSocket.any_instance.stubs(:readpartial).times(1).raises(EOFError.new)

      assert_raises(Beaneater::NotConnected) { @bc.transmit "delete 56\r\n" }
    end

    it "tubes_watched are restored after reconnect" do
      client = Beaneater.new('127.0.0.1:11300')
      client.tubes.watch! "another"

      $called = false
      TCPSocket.prepend Module.new {
        def readpartial(*)
          if !$called
            $called = true
            raise EOFError
          end

          super
        end
      }

      assert_equal %w[another], client.tubes.watched.map(&:name)
    ensure
      $called = true # the prepended readpartial stays for later tests: leave it disarmed
    end

    it "should raise NotConnected when reconnecting fails with any connect error" do
      TCPSocket.stubs(:new).raises(Errno::EHOSTUNREACH.new)
      TCPSocket.any_instance.stubs(:readpartial).raises(EOFError.new)

      assert_raises(Beaneater::NotConnected) { @bc.transmit "stats", retry_interval: 0 }
    end

    it "should reconnect on the next command after draining retries ran out" do
      TCPSocket.any_instance.stubs(:readpartial).raises(Beaneater::UnexpectedResponse.from_status("DRAINING", "stats"))
      assert_raises(Beaneater::DrainingError) { @bc.transmit "stats", retry_interval: 0 }

      TCPSocket.any_instance.unstub(:readpartial)
      assert_equal 'OK', @bc.transmit('stats')[:status]
    end

    it "should drop the connection when a command is interrupted, so the next command reads its own reply" do
      client = Beaneater.new('localhost')
      client.tubes.watch!('interrupted')
      assert_raises(Timeout::Error) { Timeout.timeout(0.3) { client.tubes.reserve } }

      producer = Beaneater.new('localhost')
      producer.tubes.find('interrupted').put('late job')
      producer.close
      sleep 0.1 # let a reserve still pending on the old socket take the job

      assert_equal %w[interrupted], client.tubes.watched.map(&:name)
      job = client.tubes.reserve(1)
      assert_equal 'late job', job.body
      job.delete
    ensure
      client.close if client
    end

    it "should keep the connection after an error reply" do
      socket = @bc.connection
      assert_raises(Beaneater::NotFoundError) { @bc.transmit 'peek 4294967295' }
      assert_same socket, @bc.connection
    end

    describe "after the server was down for longer than the reconnect retries" do
      before do
        @port = free_port
        @pid = start_beanstalkd(@port)
        @client = Beaneater.new("127.0.0.1:#{@port}")
      end

      after do
        @client.close if @client
        stop_beanstalkd(@pid) if @pid
      end

      it "reconnects on the next command and restores the used and watched tubes" do
        @client.tubes.watch('reconnect-watched')
        @client.tubes.use('reconnect-used')

        stop_beanstalkd(@pid)
        assert_raises(Beaneater::NotConnected) do
          @client.connection.transmit('list-tubes', retry_interval: 0.01)
        end

        @pid = start_beanstalkd(@port)
        assert_equal 'reconnect-used', @client.tubes.used.name
        assert_equal %w[default reconnect-watched], @client.tubes.watched.map(&:name).sort
      end

      it "lets threads sharing the client recover when the server restarts under them" do
        @client.tubes.use('restart-used')
        stop = false
        workers = 2.times.map do |i|
          Thread.new do
            until stop
              begin
                i.zero? ? @client.tubes['restart-used'].put('x') : @client.tubes.used
              rescue Beaneater::NotConnected, IOError
                sleep 0.01
              end
            end
          end
        end
        5.times do
          sleep 0.3
          stop_beanstalkd(@pid)
          @pid = start_beanstalkd(@port)
        end
        sleep 0.3
        stop = true
        stuck = workers.reject { |t| t.join(5) }
        stuck.each(&:kill)
        assert_empty stuck, "threads still blocked 5s after the last restart"
        assert_equal 'restart-used', Timeout.timeout(5) { @client.tubes.used.name }
      end

      it "does not reopen a connection closed while it was reconnecting" do
        stop_beanstalkd(@pid)
        result = nil
        worker = Thread.new do
          begin
            @client.connection.transmit('stats', retry_interval: 0.5)
            result = :answered
          rescue Exception => ex
            result = ex.class
          end
        end
        sleep 0.2 # the worker is between reconnect attempts
        @client.close
        @pid = start_beanstalkd(@port)
        assert worker.join(5), "worker still running"
        assert_equal Beaneater::NotConnected, result
        assert_nil @client.connection.connection
      end
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

    it "should unblock a reserve waiting in another thread" do
      client = Beaneater.new('localhost')
      client.tubes.watch!('close-unblocks-reserve')
      result = nil
      waiter = Thread.new do
        begin
          client.tubes.reserve
          result = :reserved
        rescue Exception => ex
          result = ex
        end
      end
      sleep 0.3 # the waiter is blocked in reserve
      client.close
      assert waiter.join(1), "reserve still blocked 1s after close"
      assert_kind_of IOError, result
    ensure
      waiter.kill if waiter
    end
  end # close
end # Beaneater::Connection
