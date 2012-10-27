require 'set'

module Beaneater
  class PoolCommand
    attr_reader :pool

    def initialize(pool)
      @pool = pool
    end

    # transmit_to_all('use foo')
    # transmit_to_all('stats', :merge => true)
    def transmit_to_all(body, options={}, &block)
      merge = options.delete(:merge)
      res = pool.transmit_to_all(body, options, &block)
      if merge
        res = { :status => res.first[:status], :body => sum_hashes(res.map { |r| r[:body] }) }
      end
      res
    end

    def method_missing(name, *args, &block)
      if pool.respond_to?(name)
        pool.send(name, *args, &block)
      else # not a known pool command
        super
      end
    end

    protected

    def sum_hashes(hs)
      hs.select { |h| h.is_a?(Hash) }.
        inject({}) { |a,b| a.merge(b) { |k,o,n| combine_stats(k, o, n) } }
    end

    def combine_stats(k, a, b)
      ['name', 'version', 'pid'].include?(k) ? Set[a] + Set[b] : a + b
    end
  end # PoolCommand
end # Beaneater