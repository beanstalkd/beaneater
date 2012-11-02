require 'beaneater/stats/fast_struct'
require 'beaneater/stats/stat_struct'

module Beaneater
  # Represents stats related to the beanstalkd pool.
  class Stats < PoolCommand
    # Returns keys for stats data
    #
    # @return [Array<String>] Set of keys for stats.
    # @example
    #  @bp.stats.keys # => ["version", "total_connections"]
    #
    # @api public
    def keys
      data.keys
    end

    # Returns value for specified key.
    #
    # @param [String,Symbol] key Name of key to retrieve
    # @return [String,Integer] Value of specified key
    # @example
    #  @bp.stats['total_connections'] # => 4
    #
    def [](key)
      data[key]
    end

    # Defines a cached method for looking up data for specified key
    # Protects against infinite loops by checking stacktrace
    # @api public
    def method_missing(name, *args, &block)
      if caller.first !~ /`(method_missing|data')/ && data.keys.include?(name.to_s)
        self.class.class_eval <<-CODE, __FILE__, __LINE__
          def #{name}; data[#{name.inspect}]; end
        CODE
        data[name.to_s]
      else # no key matches or caught infinite loop
        super
      end
    end

    protected

    # Returns struct based on stats data merged from all connections.
    #
    # @return [Beaneater::StatStruct] the combined stats for all beanstalk connections in the pool
    # @example
    #  self.data # => { 'version' : 1.7, 'total_connections' : 23 }
    #  self.data.total_connections # => 23
    #
    def data
      StatStruct.from_hash(transmit_to_all('stats', :merge => true)[:body])
    end
  end # Stats
end # Beaneater