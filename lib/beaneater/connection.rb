require 'yaml'

module Beaneater
  class Connection
    attr_accessor :telnet_connections

    DEFAULT_PORT = 11300

    # @beaneater_connection = Beaneater::Connection.new(['localhost:11300'])
    def initialize(hosts)
      init_telnet(hosts)
    end

    # transmit_to_all("stats", :match => /\n/)
    def transmit_to_all(command, options = {}, &block)
      telnet_connections.map do |tc|
        transmit_to_conn(tc, command, options, &block)
      end
    end

    # transmit_to_rand("stats", :match => /\n/)
    def transmit_to_rand(command, options = {}, &block)
      transmit_to_conn(telnet_connections.sample, command, options, &block)
    end

    def stats
      @stats ||= Stats.new(self)
    end

    def tubes
      @tubes ||= Tubes.new(self)
    end

    protected

    # transmit_to_conn(tc, "stats", :match => /\n/) { |r| puts r }
    def transmit_to_conn(telnet_connection, command, options={}, &block)
      options.merge!("String" => command)
      parse_response(telnet_connection.cmd(options, &block))
    end

    # Init telnet
    def init_telnet(hosts)
      hosts_map = parse_hosts(hosts)
      @telnet_connections ||= []
      hosts_map.each do |h|
        port = h[:port] ? h[:port].to_i : DEFAULT_PORT
        @telnet_connections << Net::Telnet.new('Host' => h[:host], "Port" => port, "Prompt" => /\n/)
      end
    end

    # Return => ["OK 456", "Body"]
    def parse_response(res)
      res_lines = res.split(/\r?\n/)
      status = res_lines.first
      status, id = status.scan(/\w+/)
      response = { :status => status, :body => YAML.load(res_lines[1..-1].join("\n")) }
      response[:id] = id if id
      response
    end

    # parse hosts
    def parse_hosts(hosts)
      hosts.map do |h|
        host, port = h.split(':')
        { :host => host, :port => port }
      end
    end
  end
end