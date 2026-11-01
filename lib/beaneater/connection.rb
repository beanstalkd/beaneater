# frozen_string_literal: true

require 'yaml'
require 'socket'
require 'io/wait'
require 'monitor'

class Beaneater
  # Represents a connection to a beanstalkd instance.
  class Connection

    # Default number of retries to send a command to a connection
    MAX_RETRIES = 3

    # Default retry interval
    DEFAULT_RETRY_INTERVAL = 1

    # Fields of the stats responses that are text even when they look numeric
    # (a tube named "1.12", a server id made only of digits). beanstalkd 1.13
    # quotes most of these, 1.12 does not.
    STRING_STAT_FIELDS = {
      'stats'      => %w(version id hostname os platform),
      'stats-job'  => %w(tube state),
      'stats-tube' => %w(name)
    }.freeze

    # @!attribute address
    #   @return [String] returns Beanstalkd server address
    #   @example
    #     @conn.address # => "localhost:11300"
    # @!attribute host
    #   @return [String] returns Beanstalkd server host
    #   @example
    #     @conn.host # => "localhost"
    # @!attribute port
    #  @return [Integer] returns Beanstalkd server port
    #  @example
    #    @conn.port # => "11300"
    # @!attribute connection
    #   @return [Net::TCPSocket] returns connection object
    attr_reader :address, :host, :port, :connection

    # @!attribute tubes_watched
    #   @returns [Array<String>] returns currently watched tube names
    # @!attribute tube_used
    #   @returns [String] returns currently used tube name
    attr_accessor :tubes_watched, :tube_used

    # Default port value for beanstalk connection
    DEFAULT_PORT = 11300

    # Initializes new connection.
    #
    # @param [String] address beanstalkd instance address.
    # @example
    #   Beaneater::Connection.new('127.0.0.1')
    #   Beaneater::Connection.new('127.0.0.1:11300')
    #
    #   ENV['BEANSTALKD_URL'] = '127.0.0.1:11300'
    #   @b = Beaneater.new
    #   @b.connection.host # => '127.0.0.1'
    #   @b.connection.port # => '11300'
    #
    def initialize(address)
      @address = address || _host_from_env || Beaneater.configuration.beanstalkd_url
      # Held for each attempt at a command (reconnecting and restoring the tubes included), not
      # across the pauses between attempts. Reentrant: a job_parser that uses this client runs
      # while its command holds the lock.
      @mutex = Monitor.new
      @tube_used = 'default'
      @tubes_watched = ['default']

      establish_connection
    rescue
      _raise_not_connected!
    end

    # Send commands to beanstalkd server via connection.
    #
    # @param [Hash{String => String, Number}>] options Retained for compatibility
    # @param [String] command Beanstalkd command
    # @return [Array<Hash{String => String, Number}>] Beanstalkd command response
    # @example
    #   @conn = Beaneater::Connection.new
    #   @conn.transmit('bury 123')
    #   @conn.transmit('stats')
    #
    def transmit(command, **options)
      state = {
        :retry_interval => options[:retry_interval] || DEFAULT_RETRY_INTERVAL, # nil too
        :init           => options.fetch(:init, true),
        :reconnects     => 0,
        :connect_tries  => MAX_RETRIES,
        :draining_tries => MAX_RETRIES,
        :connecting     => false
      }
      reentrant = @mutex.mon_owned?
      loop do
        done, value = @mutex.synchronize { _attempt(command, state) }
        return value if done
        # Pause before the next attempt with the lock released, so other threads go on and
        # Timeout or Thread#raise can stop this one. A reentrant call (from a job_parser) still
        # holds its outer command's lock here.
        sleep(value)
      end
    ensure
      # #close during a command (from its job_parser, a signal handler or another thread) only
      # shut the socket down; close it once the command is over and nothing waits on it
      @mutex.synchronize { _drop_connection if @closed && @connection } if @closed && !reentrant
    end

    # Close connection with beanstalkd server.
    #
    # @example
    #  @conn.close
    #
    def close
      @closed = true
      socket = @connection
      if @mutex.mon_locked? && @connection_pid == Process.pid
        # A thread (this one or another) is inside a command and may be waiting on the socket.
        # IO#close from a signal handler while any thread waits on that IO can crash Ruby 3.3
        # and 3.4 (segfault in IO#wait_readable) or raise ThreadError. Shut it down instead:
        # the wait ends with end-of-file, the command raises NotConnected, and its transmit
        # closes the socket on its way out. Only in the process that opened the connection: a
        # child forked during a command inherits the held lock, and shutting down would cut
        # the parent's connection; the child just closes its own copy below.
        socket.shutdown(Socket::SHUT_RDWR) if socket && !socket.closed?
      else
        # ceiling: a thread can take the lock between the check above and this close and start
        # waiting on the socket. A close from a signal handler then raises ThreadError on Ruby
        # 3.3 and 3.4 (ignored below); the waiting thread gets a TypeError from Ruby, and Ruby
        # keeps the fd open (and the server that connection's pending command) until garbage
        # collection. On 3.1, 3.2 and 4.0, and from a plain thread, the waiter gets IOError.
        # Closing under the lock would shut the window, but a signal handler cannot wait for
        # the lock.
        _drop_connection
      end
    rescue ThreadError
      nil # IO#close refused in a signal handler (see the ceiling above)
    rescue SystemCallError, IOError
      nil # already disconnected, or closed by another thread meanwhile
    end

    # Returns string representation of job.
    #
    # @example
    #  @conn.inspect
    #
    def to_s
      "#<Beaneater::Connection host=#{host.inspect} port=#{port.inspect}>"
    end
    alias :inspect :to_s

    # The watched tubes are kept by name, once each: a reconnect watches them again.
    def add_to_watched(tube_name)
      @tubes_watched << tube_name.to_s
      @tubes_watched.uniq!
      @tubes_watched
    end

    def remove_from_watched(tube_name)
      @tubes_watched.delete(tube_name.to_s)
    end

    protected

    # Establish a connection based on beanstalk address.
    #
    # @return [Net::TCPSocket] connection for specified address.
    # @raise [Beaneater::NotConnected] Could not connect to specified beanstalkd instance.
    # @example
    #  establish_connection('localhost:3005')
    #
    def establish_connection
      @address = address.first if address.is_a?(Array)
      match = address.split(':')
      @host, @port = match[0], Integer(match[1] || DEFAULT_PORT)

      tcp_opts = { connect_timeout: config.connect_timeout, resolv_timeout: config.resolv_timeout }.compact

      socket = if RUBY_VERSION >= "3.0" && tcp_opts.any?
        TCPSocket.new(@host, @port, **tcp_opts)
      else
        TCPSocket.new(@host, @port)
      end

      @read_buffer = String.new # binary; bytes read but not yet consumed
      @connection = socket
      @connection_pid = Process.pid # a forked child shares the socket; see #close
    end

    # Parses the response and returns the useful beanstalk response.
    # Will read the body if one is indicated by the status.
    #
    # @param [String] cmd Beanstalk command transmitted
    # @param [String] res Telnet command response
    # @return [Array<Hash{String => String, Number}>] Beanstalk response with `status`, `id`, `body`
    # @raise [Beaneater::UnexpectedResponse] Response from beanstalk command was an error status
    # @example
    #  parse_response("delete 56", "DELETED 56\nFOO")
    #   # => { :body => "FOO", :status => "DELETED", :id => 56 }
    #
    def parse_response(cmd, res)
      status = res.chomp
      body_values = status.split(/\s/)
      status = body_values[0]
      raise UnexpectedResponse.from_status(status, cmd) if UnexpectedResponse::ERROR_STATES.include?(status)
      body = nil
      if ['OK','FOUND', 'RESERVED'].include?(status)
        bytes_size = body_values[-1].to_i
        raw_body = _read_bytes(bytes_size, cmd)
        # Consume the trailing CRLF before parsing, so a parser that raises
        # leaves the stream at the start of the next reply.
        crlf = _read_bytes(2, cmd) # \r\n
        raise ExpectedCrlfError.new('EXPECTED_CRLF', cmd) if crlf != "\r\n"
        @reply_read = true
        body = if status == 'OK'
          parse_yaml_body(cmd, raw_body)
        else
          _parse_job(status, body_values[1], raw_body)
        end
      end
      id = body_values[1]
      response = { :status => status }
      response[:id] = id if id
      response[:body] = body if body
      response
    end

    # Parses the YAML body of an OK response (stats, stats-job, stats-tube,
    # list-tubes, list-tubes-watched). beanstalkd emits only a "---" line
    # followed by "key: value" lines or "- item" lines, so the body is parsed
    # directly rather than through a YAML loader, which would turn tube names
    # such as "2022-09-30", "1.12" or "true" into dates, numbers or booleans.
    #
    # @param [String] cmd Beanstalk command transmitted
    # @param [String] raw_body Response body
    # @return [Hash{String => String, Integer, Float, Boolean}, Array<String>] Parsed body
    # @example
    #  parse_yaml_body("stats-job 1", "---\nid: 1\ntube: email-jobs\n")
    #   # => { "id" => 1, "tube" => "email-jobs" }
    #
    def parse_yaml_body(cmd, raw_body)
      lines = raw_body.dup.force_encoding(Encoding::UTF_8).each_line.map(&:chomp)
      lines.shift if lines.first == '---'
      if lines.first && lines.first.start_with?('- ')
        lines.map { |line| _stat_value(line[2..-1], true) }
      else
        text_fields = STRING_STAT_FIELDS[cmd.to_s.split(' ').first] || []
        lines.each_with_object({}) do |line, hash|
          key, value = line.split(': ', 2)
          hash[key] = _stat_value(value.to_s, text_fields.include?(key)) unless key.to_s.empty?
        end
      end
    end

    # Runs the job_parser on a job's body. If it raises for a job this connection has just
    # reserved, a copy of the parser's exception is raised instead (same class, message,
    # backtrace and cause, so `rescue JSON::ParserError` still works), tagged with
    # Beaneater::JobParseFailure, which gives the job's id: Jobs#process! uses it to bury the job
    # instead of leaving it reserved until its TTR. A copy, so that an exception the parser
    # froze or raises again later is never changed or tagged with an old id.
    def _parse_job(status, id, raw_body)
      config.job_parser.call(raw_body)
    rescue StandardError => ex
      raise unless status == 'RESERVED'
      begin
        tagged = ex.clone(:freeze => false)
        tagged.extend(JobParseFailure)
        tagged.job_id = id
        cause = ex.cause
      rescue StandardError
        tagged = nil # it can't be copied (an initialize_clone or initialize_copy of its own)
      end
      # Re-raised out here, where $! is still ex: raised inside the rescue above, a frozen ex
      # would get the copying error as its cause and fail with "circular causes".
      raise ex unless tagged
      raise tagged, :cause => (cause if cause.is_a?(Exception))
    end

    # Returns configuration options for beaneater
    #
    # @return [Beaneater::Configuration] configuration object
    def config
      Beaneater.configuration
    end

    private

    # Sends one command and reads its whole reply, without retrying.
    def _exchange(command)
      completed = false
      outer_reply_read = @reply_read # a job_parser that uses this client runs an _exchange inside ours
      @reply_read = false # set by parse_response once the whole reply is off the socket
      unless connection
        _raise_not_connected! if @closed
        raise Errno::ENOTCONN # _attempt reconnects and restores the tubes first
      end

      command = command.dup.force_encoding('ASCII-8BIT') if command.respond_to?(:force_encoding)
      read_window = _read_window(command) # checked before anything is written
      _write(command.to_s + "\r\n", command)
      @read_deadline = _deadline_in(read_window) # bounds the status line and the body read in parse_response
      res = _read_line(command)
      response = parse_response(command, res)
      completed = true
      response
    rescue UnexpectedResponse => ex
      # an error status line is the whole reply, so the stream is still in step
      completed = !ex.is_a?(ExpectedCrlfError)
      raise
    ensure
      # Interrupted between the write and the end of the reply (Timeout, Interrupt, an I/O
      # error): the rest of the reply may still arrive, so drop the socket rather than let the
      # next command read it. The next command reconnects. Once the whole reply has been read
      # (a job_parser that raised, say) the stream is in step: keep the socket, and with it the
      # jobs this connection has reserved.
      _drop_connection unless completed || @reply_read
      @reply_read = outer_reply_read
    end

    # Restores the watched and used tubes on a new connection. Sent with _exchange, not transmit:
    # a failure here must go back to the _attempt that is reconnecting, which starts over.
    def _initialize_tubes
      if @tubes_watched != ['default']
        tubes_watched.each do |t|
          _exchange("watch #{Arguments.tube_name(t)}")
        end

        _exchange("ignore default") unless tubes_watched.include?('default')
      end

      _exchange("use #{Arguments.tube_name(tube_used)}") if @tube_used != 'default'
    end

    # One attempt at a command, made holding the lock: reconnect (and restore the tubes) if the
    # connection is gone, then send the command. Returns [true, response], or [false, seconds]
    # to pause and try again. state carries the retry counts across attempts.
    def _attempt(command, state)
      if connection
        state[:connecting] = false # another thread may have reconnected during our pause
      else
        _raise_not_connected! if @closed
        unless state[:connecting] # a new reconnect, not the next try of one in progress
          state[:reconnects] += 1
          # something accepts connections but drops every command (a proxy with no backend):
          # give up rather than reconnect in a tight loop
          _raise_not_connected! if state[:reconnects] > MAX_RETRIES
          state[:connecting] = true
          state[:connect_tries] = MAX_RETRIES
        end
        begin
          establish_connection
        rescue SystemCallError, SocketError, IOError
          state[:connect_tries] -= 1
          _raise_not_connected! if state[:connect_tries].zero?
          return [false, state[:retry_interval]]
        end
        state[:connecting] = false
        if @closed # #close ran while connecting
          _drop_connection
          _raise_not_connected!
        end
        if state[:init]
          begin
            _initialize_tubes
          rescue Exception
            # never leave a half-restored connection watching the wrong tubes: drop it, so a
            # lost connection reconnects and restores again below, and anything else makes the
            # next command start over
            _drop_connection
            raise
          end
        end
      end
      [true, _exchange(command)]
    rescue EOFError, Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED, Errno::ENOTCONN
      _drop_connection
      retry # reconnects at once, still holding the lock
    rescue Beaneater::DrainingError
      state[:draining_tries] -= 1
      if state[:draining_tries].zero?
        _drop_connection
        raise
      end
      [false, state[:retry_interval]]
    end

    # Closes the socket without marking the connection closed, so the next command reconnects.
    # Only #close is final.
    def _drop_connection
      socket, @connection = @connection, nil
      @read_buffer = String.new
      socket.close if socket
    end

    # The host provided by BEANSTALKD_URL environment variable, if available.
    #
    # @return [String] A beanstalkd host address
    # @example
    #  ENV['BEANSTALKD_URL'] = "localhost:1212"
    #   # => 'localhost:1212'
    #
    def _host_from_env
      ENV['BEANSTALKD_URL'].respond_to?(:length) && ENV['BEANSTALKD_URL'].length > 0 && ENV['BEANSTALKD_URL'].strip
    end

    # Converts one value of a stats or list response to its Ruby type:
    # quoted values and text fields stay Strings, whole numbers become
    # Integers, decimals Floats, and true/false Booleans.
    def _stat_value(value, text)
      if value.length >= 2 && value.start_with?('"') && value.end_with?('"')
        value[1..-2]
      elsif text
        value
      elsif value =~ /\A-?\d+\z/
        value.to_i
      elsif value =~ /\A-?\d+\.\d+\z/
        value.to_f
      elsif value == 'true' || value == 'false'
        value == 'true'
      else
        value
      end
    end

    # Writes data to the socket, waiting at most write_timeout seconds.
    #
    # Ruby waits on its sockets itself, so the socket-level SO_SNDTIMEO and
    # SO_RCVTIMEO options have no effect; the deadlines are kept here instead.
    def _write(data, cmd)
      deadline = _deadline_in(config.write_timeout && Float(config.write_timeout))
      until data.empty?
        written = connection.write_nonblock(data, exception: false)
        if written == :wait_writable
          _wait_for(:write, deadline, cmd)
        else
          data = data.byteslice(written..-1)
        end
      end
    end

    # Returns how many seconds the reply to cmd may take once it is written, or
    # nil to wait without limit. reserve-with-timeout gets its own timeout on top
    # of read_timeout; a plain reserve blocks until a job arrives, by design.
    # Timeouts may be given as numeric strings (from ENV, say).
    def _read_window(cmd)
      return nil if config.read_timeout.nil? || cmd =~ /\Areserve\s*\z/
      extra = cmd =~ /\Areserve-with-timeout (\d+)/ ? $1.to_i : 0
      Float(config.read_timeout) + extra
    end

    # Reads one reply line (the status line), without its line ending.
    def _read_line(cmd)
      until (eol = @read_buffer.index("\n"))
        _fill_read_buffer(cmd)
      end
      @read_buffer.slice!(0, eol + 1)
    end

    # Reads exactly size bytes of a reply body.
    def _read_bytes(size, cmd)
      _fill_read_buffer(cmd) while @read_buffer.bytesize < size
      @read_buffer.slice!(0, size)
    end

    # Waits until the socket has data (up to the reply's deadline) and appends
    # what is available to the read buffer.
    def _fill_read_buffer(cmd)
      _wait_for(:read, @read_deadline, cmd)
      @read_buffer << connection.readpartial(16_384)
    end

    # Waits for the socket to become readable or writable before deadline.
    # On timeout the connection is dropped (the next command reconnects): a late
    # reply would otherwise be read as the answer to the next command.
    #
    # @raise [Beaneater::SocketTimeout] The deadline passed.
    def _wait_for(direction, deadline, cmd)
      # Past the deadline this still polls once (timeout 0): data that is already there is
      # not a timeout.
      remaining = deadline && [deadline - _now, 0].max
      # IO#wait_* rather than IO.select: a thread waiting here is woken by end-of-file when
      # #close shuts the socket down (its command then raises NotConnected).
      ready = direction == :read ? connection.wait_readable(remaining) : connection.wait_writable(remaining)
      return if ready

      _drop_connection
      action = direction == :read ? 'waiting for the reply to' : 'writing'
      raise SocketTimeout, "Timed out #{action} '#{cmd.to_s.split("\r\n").first}' on beanstalk '#{@host}:#{@port}'; the next command reconnects"
    end

    def _deadline_in(seconds)
      seconds && _now + seconds
    end

    def _now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Raises an error to be triggered when the connection has failed
    # @raise [Beaneater::NotConnected] Beanstalkd is no longer connected
    def _raise_not_connected!
      # host and port stay unset for an address establish_connection can't parse: name it as given
      where = @host ? "#{@host}:#{@port}" : @address
      raise Beaneater::NotConnected, "Connection to beanstalk '#{where}' is closed!"
    end

  end # Connection
end # Beaneater
