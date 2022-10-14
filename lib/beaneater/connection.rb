require 'yaml'
require 'socket'

class Beaneater
  # Represents a connection to a beanstalkd instance.
  class Connection

    # Default number of retries to send a command to a connection
    MAX_RETRIES = 3

    # Default retry interval
    DEFAULT_RETRY_INTERVAL = 1

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
          _raise_not_connected! unless connection

          command = command.force_encoding('ASCII-8BIT') if command.respond_to?(:force_encoding)
          connection.write(command.to_s + "\r\n")
          res = connection.readline
          parse_response(command, res)
        end
      end
    end

    # Close connection with beanstalkd server.
    #
    # @example
    #  @conn.close
    #
    def close
      if @connection
        @connection.close
        @connection = nil
      end
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

      @connection = TCPSocket.new @host, @port
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
        raw_body = connection.read(bytes_size)
        body = if status == 'OK'
          psych_v4_valid_body = raw_body.gsub(/^(.*?): (.*)$/) { "#{$1}: #{$2.gsub(/[\:\-\~]/, '_')}" }
          YAML.load(psych_v4_valid_body)
        else
          config.job_parser.call(raw_body)
        end
        crlf = connection.read(2) # \r\n
        raise ExpectedCrlfError.new('EXPECTED_CRLF', cmd) if crlf != "\r\n"
      end
      id = body_values[1]
      response = { :status => status }
      response[:id] = id if id
      response[:body] = body if body
      response
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

        transmit("ignore default", init: false)
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
      Errno::ECONNREFUSED => ex
      _reconnect(ex, retry_interval)
      _initialize_tubes if init
      retry
    rescue Beaneater::DrainingError
      tries -= 1
      if tries.zero?
        close
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
      close
      establish_connection
    rescue Errno::ECONNREFUSED
      tries -= 1
      if tries.zero?
        _raise_not_connected!
      end
      sleep(retry_interval || DEFAULT_RETRY_INTERVAL)
      retry
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

    # Raises an error to be triggered when the connection has failed
    # @raise [Beaneater::NotConnected] Beanstalkd is no longer connected
    def _raise_not_connected!
      raise Beaneater::NotConnected, "Connection to beanstalk '#{@host}:#{@port}' is closed!"
    end

  end # Connection
end # Beaneater
