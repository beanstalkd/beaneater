require 'yaml'

module Beaneater
  class Connection
    attr_reader :telnet_connection, :host, :port

    DEFAULT_PORT = 11300

    # @beaneater_connection = Beaneater::Connection.new(['localhost:11300'])
    def initialize(address)
      @telnet_connection = connect(address)
    end

    # transmit("stats", :match => /\n/) { |r| puts r }
    def transmit(command, options={}, &block)
      options.merge!("String" => command)
      parse_response(telnet_connection.cmd(options, &block))
    end

    def to_s
      "#<Beaneater::Connection host=#{host.inspect} port=#{port.inspect}>"
    end
    alias :inspect :to_s

    protected

    # Init telnet
    # connect('localhost:3005')
    def connect(address)
      @match = address.split(':')
      @host, @port = @match[0], Integer(@match[1] || DEFAULT_PORT)
      Net::Telnet.new('Host' => @host, "Port" => @port, "Prompt" => /\n/)
    end

    # Return => ["OK 456", "Body"]
    def parse_response(res)
      res_lines = res.split(/\r?\n/)
      status = res_lines.first
      status, id = status.scan(/\w+/)
      response = { :status => status, :body => YAML.load(res_lines[1..-1].join("\n")) }
      response[:id] = id if id
      response[:connection] = self
      response
    end
  end
end