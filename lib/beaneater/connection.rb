# frozen_string_literal: true

require 'yaml'
require 'socket'

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
      @mutex = Mutex.new
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
      _with_retry(**options.slice(:retry_interval, :init)) do
        @mutex.synchronize do
          completed = false
          @reply_read = false # set by parse_response once the whole reply is off the socket
          unless connection
            _raise_not_connected! if @closed
            # lost after a failure: _with_retry reconnects, restores the tubes and retries
            raise Errno::ENOTCONN
          end

          command = command.dup.force_encoding('ASCII-8BIT') if command.respond_to?(:force_encoding)
          _write(command.to_s + "\r\n", command)
          @read_deadline = _read_deadline(command) # bounds the status line and the body read in parse_response
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
        end
      end
    end

    # Close connection with beanstalkd server.
    #
    # @example
    #  @conn.close
    #
    def close
      @closed = true
      _drop_connection
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

    def add_to_watched(tube_name)
      @tubes_watched << tube_name
      @tubes_watched.uniq
    end

    def remove_from_watched(tube_name)
      @tubes_watched.delete(tube_name)
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
          config.job_parser.call(raw_body)
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

    # Returns configuration options for beaneater
    #
    # @return [Beaneater::Configuration] configuration object
    def config
      Beaneater.configuration
    end

    private

    def _initialize_tubes
      if @tubes_watched != ['default']
        tubes_watched.each do |t|
          transmit("watch #{t}", init: false)
        end

        transmit("ignore default", init: false) unless tubes_watched.include?('default')
      end

      transmit("use #{tube_used}", init: false) if @tube_used != 'default'
    end

    # Wrapper method for capturing certain failures and retry the payload block
    #
    # @param [Proc] block The command to execute.
    # @param [Integer] retry_interval The time to wait before the next retry
    # @param [Integer] tries The maximum number of tries in draining mode
    # @return [Object] Result of the block passed
    #
    def _with_retry(retry_interval: DEFAULT_RETRY_INTERVAL, init: true, tries: MAX_RETRIES, &block)
      yield
    rescue EOFError, Errno::ECONNRESET, Errno::EPIPE,
      Errno::ECONNREFUSED, Errno::ENOTCONN => ex
      _reconnect(ex, retry_interval)
      _initialize_tubes if init
      retry
    rescue Beaneater::DrainingError
      tries -= 1
      if tries.zero?
        _drop_connection
        raise
      end
      sleep(retry_interval)
      retry
    end

    # Tries to re-establish connection to the beanstalkd
    #
    # @param [Exception] original_exception The exception caused the retry
    # @param [Integer] retry_interval The time to wait before the next reconnect
    # @param [Integer] tries The maximum number of attempts to reconnect
    def _reconnect(original_exception, retry_interval, tries=MAX_RETRIES)
      _drop_connection
      establish_connection
    rescue SystemCallError, SocketError, IOError
      tries -= 1
      if tries.zero?
        _raise_not_connected!
      end
      sleep(retry_interval || DEFAULT_RETRY_INTERVAL)
      retry
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
      deadline = _deadline_in(config.write_timeout)
      until data.empty?
        written = connection.write_nonblock(data, exception: false)
        if written == :wait_writable
          _wait_for(:write, deadline, cmd)
        else
          data = data.byteslice(written..-1)
        end
      end
    end

    # Returns the time by which the reply to cmd must have arrived, or nil to
    # wait without limit. reserve-with-timeout gets its own timeout on top of
    # read_timeout; a plain reserve blocks until a job arrives, by design.
    def _read_deadline(cmd)
      return nil if config.read_timeout.nil? || cmd =~ /\Areserve\s*\z/
      extra = cmd =~ /\Areserve-with-timeout (\d+)/ ? $1.to_i : 0
      _deadline_in(config.read_timeout + extra)
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
      remaining = deadline && deadline - _now
      ready = if remaining.nil? || remaining > 0
        readers, writers = direction == :read ? [[connection], nil] : [nil, [connection]]
        IO.select(readers, writers, nil, remaining)
      end
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
      raise Beaneater::NotConnected, "Connection to beanstalk '#{@host}:#{@port}' is closed!"
    end

  end # Connection
end # Beaneater
