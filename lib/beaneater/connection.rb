require 'yaml'

module Beaneater
  class Connection
    attr_reader :telnet_connection, :address, :host, :port

    DEFAULT_PORT = 11300
    MAX_RETRIES = 3

    # @beaneater_connection = Beaneater::Connection.new(['localhost:11300'])
    def initialize(address)
      @address = address
      @telnet_connection = establish_connection
    end

    # transmit("stats", :match => /\n/) { |r| puts r }
    def transmit(command, options={}, &block)
      options.merge!("String" => command, "FailEOF" => true)
      parse_response(command, telnet_call(options, &block))
    end

    def to_s
      "#<Beaneater::Connection host=#{host.inspect} port=#{port.inspect}>"
    end
    alias :inspect :to_s

    protected

    # Init telnet
    # establish_connection('localhost:3005')
    def establish_connection
      @match = address.split(':')
      @host, @port = @match[0], Integer(@match[1] || DEFAULT_PORT)
      Net::Telnet.new('Host' => @host, "Port" => @port, "Prompt" => /\n/)
    rescue Errno::ECONNREFUSED => e
      raise NotConnected, "Could not connect to '#{@host}:#{@port}'"
    rescue Exception => ex
      raise NotConnected, "#{ex.class}: #{ex}"
    end

    # Return => ["OK 456", "Body"]
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

    # telnet_call 'stats'
    # options: "String", "Match", "Timeout", "FailEOF"
    def telnet_call(*args, &block)
      retries = 0
      begin
        telnet_connection.cmd(*args, &block)
      rescue EOFError, Errno::ECONNRESET, Errno::EPIPE => ex
        @telnet_connection = establish_connection
        if retries < MAX_RETRIES
          retries += 1
          retry
        else # finished retrying, fail out
          raise(NotConnected, "Could not call '#{@host}:#{@port}'")
        end
      rescue DrainingError # TODO actually raise this draining error, and handle
        # Don't reconnect -- we're not interested in this server
        # retry
      end
    end # telnet_call
  end # Connection
end # Beaneater