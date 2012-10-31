require 'yaml'

module Beaneater
  class Connection
    attr_reader :telnet_connection, :address, :host, :port

    DEFAULT_PORT = 11300

    # @beaneater_connection = Beaneater::Connection.new(['localhost:11300'])
    def initialize(address)
      @address = address
      @telnet_connection = establish_connection
    end

    # transmit("stats", :match => /\n/) { |r| puts r }
    def transmit(command, options={}, &block)
      options.merge!("String" => command, "FailEOF" => true)
      parse_response(command, telnet_connection.cmd(options, &block))
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
  end # Connection
end # Beaneater