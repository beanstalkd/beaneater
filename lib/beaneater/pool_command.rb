require 'set'

module Beaneater
  # Represents collection of pool related commands.
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

    # Delegate to Pool#transmit_to_all and if needed will merge responses from beanstalkd.
    #
    # @param [String] body Beanstalkd command
    # @param [Hash{String => String, Boolean}] options socket connections options
    # @option options [Boolean] merge Ask for merging responses or not
    # @param [Proc] block Block passed in socket connection object
    # @example
    #   @pool.transmit_to_all("stats")
    #
    def transmit_to_all(body, options={}, &block)
      merge = options.delete(:merge)
      res = pool.transmit_to_all(body, options, &block)
      first = res.find { |r| r && r[:status] }
      if first && merge
        res = { :status => first[:status], :body => sum_items(res.map { |r| r[:body] }) }
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

    # Selects items from collection and then merges the individual values
    # Supports array of hashes or array of arrays
    #
    # @param [Array<Hash, Array>] hs Collection of responses returned from beanstalkd
    # @return [Hash{Symbol => String}] Merged responses combining values from all the hash bodies
    # @example
    #  self.sum_items([{ :foo => 1, :bar => 5 }, { :foo => 2, :bar => 3 }])
    #    => { :foo => 3, :bar => 8 }
    #  self.sum_items([['foo', 'bar'], ['foo', 'bar', 'baz']])
    #    => ['foo', 'bar', 'baz']
    #
    def sum_items(items)
      if items.first.is_a?(Hash)
        items.select { |h| h.is_a?(Hash) }.
          inject({}) { |a,b| a.merge(b) { |k,o,n| combine_stats(k, o, n) } }
      elsif items.first.is_a?(Array)
        items.flatten.uniq
      end
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