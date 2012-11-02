require 'yaml'

module Beaneater
  # Represents a connection to a beanstalkd instance.
  class Connection

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
    # @!attribute telnet_connection
    #   @return [Net::Telnet] returns Telnet connection object
    attr_reader :address, :host, :port, :telnet_connection

    # Default port value for beanstalk connection
    DEFAULT_PORT = 11300

    # Initializes new connection.
    #
    # @param [String] address beanstalkd instance address.
    # @example
    #   Beaneater::Connection.new('localhost')
    #   Beaneater::Connection.new('localhost:11300')
    #
    def initialize(address)
      @address = address
      @telnet_connection = establish_connection
      @mutex = Mutex.new
    end

    # Send commands to beanstalkd server via telnet_connection.
    #
    # @param [String] command Beanstalkd command
    # @param [Hash{Symbol => String,Boolean}] options Settings for telnet
    # @option options [Boolean] FailEOF raises EOF Exeception
    # @return [Array<Hash{String => String, Number}>] Beanstalkd command response
    # @example
    #   @conn.transmit('bury 123')
    #
    def transmit(command, options={}, &block)
      @mutex.lock
      if telnet_connection
        options.merge!("String" => command, "FailEOF" => true)
        parse_response(command, telnet_connection.cmd(options, &block))
      else # no telnet_connection
        raise NotConnected, "Connection to beanstalk '#{@host}:#{@port}' is closed!" unless telnet_connection
      end
    ensure
      @mutex.unlock
    end

    # Close connection with beanstalkd server.
    #
    # @example
    #  @conn.close
    #
    def close
      @telnet_connection.close
      @telnet_connection = nil
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

    protected

    # Establish a telnet connection based on beanstalk address.
    #
    # @return [Net::Telnet] telnet connection for specified address.
    # @raise [Beanstalk::NotConnected] Could not connect to specified beanstalkd instance.
    # @example
    #  establish_connection('localhost:3005')
    #
    def establish_connection
      @match = address.split(':')
      @host, @port = @match[0], Integer(@match[1] || DEFAULT_PORT)
      Net::Telnet.new('Host' => @host, "Port" => @port, "Prompt" => /\n/)
    rescue Errno::ECONNREFUSED => e
      raise NotConnected, "Could not connect to '#{@host}:#{@port}'"
    rescue Exception => ex
      raise NotConnected, "#{ex.class}: #{ex}"
    end

    # Parses the telnet response and returns the useful beanstalk response.
    #
    # @param [String] cmd Beanstalk command transmitted
    # @param [String] res Telnet command response
    # @return [Array<Hash{String => String, Number}>] Beanstalk response with `status`, `id`, `body`, and `connection`
    # @raise [Beaneater::UnexpectedResponse] Response from beanstalk command was an error status
    # @example
    #  parse_response("delete 56", "DELETED 56\nFOO")
    #   # => { :body => "FOO", :status => "DELETED", :id => 56, :connection => <Connection>  }
    #
    def parse_response(cmd, res)
      res_lines = res.split(/\r?\n/)
      status = res_lines.first
      status, id = status.scan(/\w+/)
      raise UnexpectedResponse.from_status(status, cmd) if UnexpectedResponse::ERROR_STATES.include?(status)
      response = { :status => status, :body => YAML.load(res_lines[1..-1].join("\n")) }
      response[:id] = id if id
      response[:connection] = self
      response
    end
  end # Connection
end # Beaneater