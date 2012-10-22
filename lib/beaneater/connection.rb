module Beaneater
  class Connection
    attr_accessor :sockets

    DEFAULT_PORT = 11300

    # @beaneater_connection = Beaneater::Connection.new(['localhost:11300'])
    def initialize(hosts)
      init_telnet(hosts)
    end

    protected

    # Init telnet
    def init_telnet(hosts)
      hosts_map = parse_hosts(hosts)
      @sockets ||= []
      hosts_map.each do |h|
        port = h[:port].present? ? h[:port].to_i : DEFAULT_PORT
        @sockets << TCPSocket.new(h[:host], port)
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