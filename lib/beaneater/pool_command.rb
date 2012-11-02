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

    # Delegate missing methods to pool
    def method_missing(name, *args, &block)
      if pool.respond_to?(name)
        pool.send(name, *args, &block)
      else # not a known pool command
        super
      end
    end

    protected

    # Selects hashes from collection and then merges the individual key values
    #
    # @param [Array<Hash>] hs Collection of hash responses returned from beanstalkd
    # @return [Hash] Merged responses combining values from all the hash bodies
    # @example
    #  self.sum_hashes([{ :foo => 1, :bar => 5 }, { :foo => 2, :bar => 3 }])
    #    => { :foo => 3, :bar => 8 }
    #
    def sum_hashes(hs)
      hs.select { |h| h.is_a?(Hash) }.
        inject({}) { |a,b| a.merge(b) { |k,o,n| combine_stats(k, o, n) } }
    end

    # Combine two values for given key
    #
    # @param [String] k key name within response hash
    # @return [Set,Integer] combined value for stat
    # @example
    #  self.combine_stats('total_connections', 4, 5) # => 9
    #
    def combine_stats(k, a, b)
      ['name', 'version', 'pid'].include?(k) ? Set[a] + Set[b] : a + b
    end
  end # PoolCommand
end # Beaneater