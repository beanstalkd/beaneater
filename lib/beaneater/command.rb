require 'set'

module Beaneater
  class Command
    attr_reader :connection

    def initialize(connection)
      @connection = connection
    end

    # transmit_to_all('use foo')
    # transmit_to_all('stats', :merge => true)
    def transmit_to_all(body, options={}, &block)
      merge = options.delete(:merge)
      res = connection.transmit_to_all(body, options, &block)
      if merge
        res = { :status => res.first[:status], :body => sum_hashes(res.map { |r| r[:body] }) }
      end
      res
    end

    def method_missing(name, *args, &block)
      if connection.respond_to?(name)
        connection.send(name, *args, &block)
      else
        super
      end
    end

    protected

    def sum_hashes(hs)
      hs.inject({}){ |a,b| a.merge(b) { |k,o,n| combine_stats(k, o, n)}}
    end

    def combine_stats(k, a, b)
      ['name', 'version', 'pid'].include?(k) ? Set[a] + Set[b] : a + b
    end
  end
end