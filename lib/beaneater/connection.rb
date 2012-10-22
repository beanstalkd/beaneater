module Beaneater
  class Connection
    attr_accessor :telnet_connections

    DEFAULT_PORT = 11300

    # @beaneater_connection = Beaneater::Connection.new(['localhost:11300'])
    def initialize(addresses)
      init_telnet(addresses)
    end

    protected

    # Init telnet
    def init_telnet(addresses)
      addresses_map = parse_addresses(addresses)
      @telnet_connections ||= []
      addresses_map.each do |a|
        port = a[:port].present? ? a[:port].to_i : DEFAULT_PORT
        @telnet_connections << Net::Telnet::new("Host" => a[:address], "Port" => port)
      end
    end

    # retrieve port
    def parse_addresses(addresses)
      addresses.map do |a|
        match = /^(?<address>(\w|\.)*)(:?)(?<port>\d*)$/.match(a)
        { :address => match[:address], :port => match[:port] }
      end
    end
  end
end