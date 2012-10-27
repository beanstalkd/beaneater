require 'yaml'

module Beaneater
  class Connection
    attr_accessor :telnet_connection

    DEFAULT_PORT = 11300

    # @beaneater_connection = Beaneater::Connection.new(['localhost:11300'])
    def initialize(host)
      @telnet_connection = connect(host)
    end

    # transmit("stats", :match => /\n/) { |r| puts r }
    def transmit(command, options={}, &block)
      options.merge!("String" => command)
      parse_response(telnet_connection.cmd(options, &block))
    end

    protected

    # Init telnet
    # connect('localhost:3005')
    def connect(host)
      host, port = host.split(':')
      Net::Telnet.new('Host' => host, "Port" => (port || DEFAULT_PORT).to_i, "Prompt" => /\n/)
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