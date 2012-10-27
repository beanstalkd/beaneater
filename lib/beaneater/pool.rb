module Beaneater
  class Pool
    attr_reader :connections

    def initialize(hosts)
      @connections = hosts.map { |h| Connection.new(h) }
    end

    def stats
      @stats ||= Stats.new(self)
    end

    def tubes
      @tubes ||= Tubes.new(self)
    end

    # transmit_to_all("stats", :match => /\n/)
    def transmit_to_all(command, options={}, &block)
      connections.map do |c|
        c.transmit(command, options, &block)
      end
    end

    # transmit_to_rand("stats", :match => /\n/)
    def transmit_to_rand(command, options={}, &block)
      conn = connections.sample
      conn.transmit(command, options, &block)
    end

    # transmit_until_res('peek-ready', :status => "FOUND", &block)
    def transmit_until_res(command, options={}, &block)
      status_expected  = options.delete(:status)
      connections.each do |c|
        res = c.transmit(command, options, &block)
        return res if res[:status] == status_expected
      end
      nil
    end
  end
end