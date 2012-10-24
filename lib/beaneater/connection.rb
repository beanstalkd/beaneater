require 'yaml'

module Beaneater
  class Connection
    attr_accessor :telnet_connections

    DEFAULT_PORT = 11300

    # @beaneater_connection = Beaneater::Connection.new(['localhost:11300'])
    def initialize(hosts)
      init_telnet(hosts)
    end

    # cmd("stats", :match => /\n/)
    def cmd(command, options = {}, &block)
      telnet_connections.map do |tc|
        options.merge!("String" => command)
        parse_response(tc.cmd(options))
      end
    end
    protected

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
      { :status => status, :body => YAML.load(res_lines[1..-1].join("\n")) }
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