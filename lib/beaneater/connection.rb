module Beaneater
  class Connection
    attr_accessor :telnet_connections

    DEFAULT_PORT = 11300

    # @beaneater_connection = Beaneater::Connection.new(['localhost:11300'])
    def initialize(hosts)
      init_telnet(hosts)
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

    # parse hosts
    def parse_hosts(hosts)
      hosts.map do |h|
        host, port = h.split(':')
        { :host => host, :port => port }
      end
    end
  end
end