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
      error = assert_raises(Beaneater::NotConnected) { Beaneater::Connection.new("localhost:8544") }
      assert_equal "Connection to beanstalk 'localhost:8544' is closed!", error.message
    end

    it "should leave the user and password out of the address it names" do
      { 'user:secret@127.0.0.1:1'                 => '127.0.0.1:1',
        'beanstalk://user:secret@127.0.0.1:11300' => 'beanstalk://127.0.0.1:11300',
        'user@localhost:8544'                     => 'localhost:8544' }.each do |address, shown|
        error = assert_raises(Beaneater::NotConnected) { Beaneater::Connection.new(address) }
        assert_equal "Connection to beanstalk '#{shown}' is closed!", error.message
      end
    end

    it "should name an address it can't parse as given" do
      ['[::1]:11300', '::1', 'beanstalk://127.0.0.1:11300'].each do |address|
        error = assert_raises(Beaneater::NotConnected) { Beaneater::Connection.new(address) }
        assert_equal "Connection to beanstalk '#{address}' is closed!", error.message
      end
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

    it "should accept timeouts given as numeric strings" do
      Beaneater.configure do |config|
        config.read_timeout  = '0.5'
        config.write_timeout = '0.5'
      end
      with_silent_server do |address|
        bc = Beaneater::Connection.new(address)
        assert_raises(Beaneater::SocketTimeout) { Timeout.timeout(5) { bc.transmit('stats') } }
      end
    end

    it "should read a reply that is already there when the deadline has passed" do
      Beaneater.configure { |config| config.read_timeout = 0 }
      server = TCPServer.new('127.0.0.1', 0)
      # answers before the command arrives, so the reply is waiting when the client polls
      responder = Thread.new { peer = server.accept; peer.write("USING eager\r\n"); peer }
      bc = Beaneater::Connection.new("127.0.0.1:#{server.addr[1]}")
      peer = responder.value
      sleep 0.2
      res = bc.transmit('use eager')
      assert_equal 'USING', res[:status]
      assert_equal 'eager', res[:id]
    ensure
      peer.close if peer
      server.close if server
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
      socket = client.connection.connection
      socket.expects(:readpartial).once.raises(EOFError.new) # this socket only

      assert_equal %w[another], client.tubes.watched.map(&:name)
      refute_same socket, client.connection.connection
    ensure
      client.close if client
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

    it "restores the watched tubes again when the connection drops while restoring them" do
      # A minimal beanstalkd that drops the 1st connection on 'stats' and the 2nd on 'ignore'
      server = TCPServer.new('127.0.0.1', 0)
      accepted = 0
      fake = Thread.new do
        loop do
          sock = server.accept
          accepted += 1
          Thread.new(sock, accepted) do |peer, n|
            watched = ['default']
            while (line = peer.gets("\r\n"))
              cmd, arg = line.chomp("\r\n").split(' ', 2)
              if (n == 1 && cmd == 'stats') || (n == 2 && cmd == 'ignore')
                peer.close
                break
              end
              reply = case cmd
                when 'watch' then watched |= [arg]; "WATCHING #{watched.size}\r\n"
                when 'ignore'
                  if watched == [arg] then "NOT_IGNORED\r\n"
                  else watched -= [arg]; "WATCHING #{watched.size}\r\n"
                  end
                when 'list-tubes-watched', 'stats'
                  body = cmd == 'stats' ? "---\nuptime: 1\n" : "---\n" + watched.map { |t| "- #{t}\n" }.join
                  "OK #{body.bytesize}\r\n#{body}\r\n"
                else "UNKNOWN_COMMAND\r\n"
              end
              peer.write(reply)
            end
          end
        end
      end
      client = Beaneater.new("127.0.0.1:#{server.addr[1]}")
      client.tubes.watch!('restore-a', 'restore-b')

      assert_equal({ 'uptime' => 1 }, Timeout.timeout(5) { client.connection.transmit('stats', retry_interval: 0)[:body] })
      assert_equal %w[restore-a restore-b], client.tubes.watched.map(&:name)
      assert_equal 3, accepted
    ensure
      client.close if client
      fake.kill if fake
      server.close if server
    end

    it "gives up when every new connection is dropped as soon as a command is sent" do
      # like a proxy that accepts connections while its backend is down
      server = TCPServer.new('127.0.0.1', 0)
      accepted = 0
      acceptor = Thread.new do
        loop do
          peer = server.accept
          accepted += 1
          if accepted == 1
            Thread.new(peer) { |p| p.gets("\r\n"); p.write("USING x\r\n"); p.gets("\r\n"); p.close }
          else
            Thread.new(peer) { |p| p.gets("\r\n"); p.close }
          end
        end
      end
      bc = Beaneater::Connection.new("127.0.0.1:#{server.addr[1]}")
      assert_equal 'USING', bc.transmit('use x')[:status]
      assert_raises(Beaneater::NotConnected) { Timeout.timeout(5) { bc.transmit('stats', retry_interval: 0) } }
      assert_operator accepted, :<=, Beaneater::Connection::MAX_RETRIES + 1
    ensure
      acceptor.kill if acceptor
      server.close if server
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

      it "lets threads sharing the client wait out their reconnect retries side by side" do
        stop_beanstalkd(@pid)
        now = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        started = now.call
        waits = 4.times.map do
          Thread.new do
            t = now.call
            begin
              @client.connection.transmit('stats', retry_interval: 0.5)
            rescue Beaneater::NotConnected
            end
            now.call - t
          end
        end.map(&:value)
        # each thread waits out about 1 s of retries; one after another that would be 4 s
        assert_operator now.call - started, :<, 2, "waits: #{waits.inspect}"

        @pid = start_beanstalkd(@port)
        assert_equal 'OK', @client.connection.transmit('stats')[:status]
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

    describe "while the server is draining" do
      before do
        @port = free_port
        @pid = start_beanstalkd(@port)
        @client = Beaneater.new("127.0.0.1:#{@port}")
      end

      after do
        @client.close if @client
        stop_beanstalkd(@pid) if @pid
      end

      it "lets threads sharing the client wait out their draining retries side by side" do
        Process.kill('USR1', @pid) # beanstalkd answers DRAINING to put from now on
        sleep 0.2
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        errors = 4.times.map do
          Thread.new do
            begin
              @client.connection.transmit("put 0 0 100 1\r\nx", retry_interval: 0.3)
            rescue Beaneater::DrainingError => ex
              ex.class
            end
          end
        end.map(&:value)
        assert_equal [Beaneater::DrainingError] * 4, errors
        # each put waits 2 x 0.3 s between its tries; one after another that would be 2.4 s
        assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.5
      end

      it "lets Timeout stop a command pausing between retries while another thread holds the client" do
        @client.tubes.find('slow-parse').put('slow')
        @client.tubes.watch!('slow-parse')
        Process.kill('USR1', @pid) # draining: put is refused, reserve still works
        sleep 0.2
        Beaneater.configure.job_parser = lambda { |body| sleep 2 if body == 'slow'; body }
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        put = Thread.new do
          begin
            Timeout.timeout(0.5) { @client.connection.transmit("put 0 0 100 1\r\nx", retry_interval: 0.3) }
          rescue Exception => ex
            [ex.class, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
          end
        end
        sleep 0.1 # the put got DRAINING and is pausing before its next try
        holder = Thread.new { @client.connection.transmit('reserve-with-timeout 0') } # holds the client ~2 s
        error, at = put.value
        holder.join
        assert_equal Timeout::Error, error
        assert_operator at, :<, 1, "Timeout fired after #{at.round(2)}s"
      ensure
        Beaneater.configure.job_parser = lambda { |body| body }
      end

      it "uses the default retry interval between DRAINING retries when given nil" do
        Process.kill('USR1', @pid)
        sleep 0.2
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        assert_raises(Beaneater::DrainingError) do
          Timeout.timeout(5) { @client.connection.transmit("put 0 0 100 1\r\nx", retry_interval: nil) }
        end
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        assert_in_delta 2 * Beaneater::Connection::DEFAULT_RETRY_INTERVAL, elapsed, 0.5
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

    # Removes the job a test left in tube name. Its client was closed with the job reserved, so
    # wait (briefly) for the server to release it before clearing the tube.
    def clear_after_close(name)
      cleaner = Beaneater.new('localhost')
      20.times do
        cleanup_tubes!([name], cleaner)
        stats = begin
          cleaner.tubes.find(name).stats
        rescue Beaneater::NotFoundError
          break # the tube is gone: no jobs left
        end
        break if stats.current_jobs_reserved.zero? && stats.current_jobs_ready.zero?
        sleep 0.05
      end
    ensure
      cleaner.close if cleaner
    end

    it "should close the socket once a command whose job_parser closed the client is over" do
      client = Beaneater.new('localhost')
      client.tubes.find('close-from-parser').put('x')
      client.tubes.watch!('close-from-parser')
      socket = client.connection.connection
      Beaneater.configure.job_parser = lambda { |body| client.close; body }
      assert_equal 'x', client.tubes.reserve(0).body
      assert_nil client.connection.connection
      assert socket.closed?, "the shut-down socket is still open"
    ensure
      Beaneater.configure.job_parser = lambda { |body| body }
      clear_after_close('close-from-parser')
    end

    it "should not raise when the socket is closed by another thread while #close shuts it down" do
      client = Beaneater.new('localhost')
      client.tubes.find('close-race').put('x')
      client.tubes.watch!('close-race')
      client.connection.connection.stubs(:shutdown).raises(IOError, 'closed stream')
      Beaneater.configure.job_parser = lambda { |body| client.close; body }
      assert_equal 'x', client.tubes.reserve(0).body
    ensure
      Beaneater.configure.job_parser = lambda { |body| body }
      clear_after_close('close-race')
    end

    describe "in a forked child" do
      before do
        skip("needs fork") unless Process.respond_to?(:fork)
        @client = Beaneater.new('localhost')
        cleanup_tubes!(['fork-close'], @client)
        @client.tubes.find('fork-close').put('work')
        @client.tubes.watch!('fork-close')
      end

      after do
        Beaneater.configure.job_parser = lambda { |body| body }
        @client.close if @client
        cleaner = Beaneater.new('localhost')
        cleanup_tubes!(['fork-close'], cleaner) # a failed run leaves the job behind
        cleaner.close
      end

      # The parent still holds the job it reserved: another client cannot get it, and the
      # parent can delete it on its own connection.
      def assert_parent_keeps(job)
        other = Beaneater.new('localhost')
        other.tubes.watch!('fork-close')
        assert_raises(Beaneater::TimedOutError) { other.tubes.reserve(0) }
        assert_equal 'DELETED', @client.connection.transmit("delete #{job.id}")[:status]
      ensure
        other.close if other
      end

      it "should leave the parent's connection alone" do
        job = @client.tubes.reserve(0)
        child = fork { @client.close; exit!(0) }
        Process.wait(child)
        assert_parent_keeps(job)
      end

      it "should leave the parent's connection alone when forked during a command" do
        child = nil
        Beaneater.configure.job_parser = lambda { |body| child = fork { @client.close; exit!(0) }; body }
        job = @client.tubes.reserve(0)
        Beaneater.configure.job_parser = lambda { |body| body } # no second fork if anything below fails
        Process.wait(child)
        assert_parent_keeps(job)
      end
    end

    it "should end a reserve when a signal handler on the same thread closes the client" do
      # Guards the contract: the reserve ends with NotConnected. It also runs the case that
      # crashed Ruby 3.3 (closing the socket under the wait), but that crash came in about one
      # run in four, so 20 runs catch it with high probability, not certainty. A child process
      # keeps a crash from taking the suite down.
      script = <<-RUBY
        require 'beaneater'
        20.times do
          client = Beaneater.new('localhost')
          client.tubes.watch!('close-from-trap')
          Signal.trap('USR2') { client.close }
          Thread.new { sleep 0.05; Process.kill('USR2', Process.pid) }
          puts(begin; client.tubes.reserve; 'reserved'; rescue Exception => ex; ex.class.name; end)
        end
      RUBY
      lib = File.expand_path('../../lib', __FILE__)
      out = IO.popen([RbConfig.ruby, '-I', lib, '-e', script]) do |child|
        begin
          Timeout.timeout(60) { child.read }
        rescue Timeout::Error
          Process.kill('KILL', child.pid)
          flunk "the child was still running after 60s"
        end
      end
      assert $?.success?, "child failed (#{$?.inspect}) after: #{out.lines.size} reserves"
      assert_equal ['Beaneater::NotConnected'] * 20, out.lines.map(&:chomp)
    end

    it "should end a reserve in another thread when a signal handler closes the client" do
      # Same contract and same caveat as the test above (the 3.3 crash is caught only with high
      # probability), with the reserve in a second thread and the main thread idle.
      script = <<-RUBY
        require 'beaneater'
        20.times do
          client = Beaneater.new('localhost')
          client.tubes.watch!('close-from-trap-other-thread')
          trap_error = '-'
          Signal.trap('USR2') do
            begin
              client.close
            rescue Exception => ex
              trap_error = ex.class.name
            end
          end
          waiter = Thread.new { begin; client.tubes.reserve; 'reserved'; rescue Exception => ex; ex.class.name; end }
          sleep 0.05 # the waiter is blocked in reserve
          Process.kill('USR2', Process.pid)
          puts "\#{waiter.join(5) ? waiter.value : 'still blocked'} \#{trap_error}"
        end
      RUBY
      lib = File.expand_path('../../lib', __FILE__)
      out = IO.popen([RbConfig.ruby, '-I', lib, '-e', script]) do |child|
        begin
          Timeout.timeout(60) { child.read }
        rescue Timeout::Error
          Process.kill('KILL', child.pid)
          flunk "the child was still running after 60s"
        end
      end
      assert $?.success?, "child failed (#{$?.inspect}) after: #{out.lines.size} reserves"
      assert_equal ['Beaneater::NotConnected -'] * 20, out.lines.map(&:chomp)
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
      assert_kind_of Beaneater::NotConnected, result
      assert_nil client.connection.connection
    ensure
      waiter.kill if waiter
    end
  end # close
end # Beaneater::Connection
