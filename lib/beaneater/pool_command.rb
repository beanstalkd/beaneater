require 'set'

module Beaneater
  class PoolCommand
    # @!attribute pool
    #   @return [Beaneater::Pool] returns Pool object
    attr_reader :pool

    # Initialize new connection
    #
    # @param [Beaneater::Pool] pool Pool object
    def initialize(pool)
      @pool = pool
    end

    # Delegate to Pool#transmit_to_all and if needed will merge responses from beanstalkd
    #
    # @param [String] body Beanstalkd command
    # @param [Hash] options telnet connections options
    # @option options [Boolean] merge Ask for merging responses or not
    # @param [Proc] block Block passed in telnet connection object
    #
    # @example
    #   @pool.transmit_to_all("stats")
    def transmit_to_all(body, options={}, &block)
      merge = options.delete(:merge)
      res = pool.transmit_to_all(body, options, &block)
      if merge
        res = { :status => res.first[:status], :body => sum_hashes(res.map { |r| r[:body] }) }
      end
      res
    end

    # Delegate missing methods to pool
    # @api public
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