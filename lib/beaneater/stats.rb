require 'beaneater/stats/fast_struct'
require 'beaneater/stats/stat_struct'

class Beaneater
  # Represents stats related to the beanstalkd pool.
  class Stats

    # @!attribute client
    #   @return [Beaneater] returns the client instance
    attr_reader :client

    # Creates new stats instance.
    #
    # @param [Beaneater] client The beaneater client instance.
    # @example
    #  Beaneater::Stats.new(@client)
    #
    def initialize(client)
      @client = client
    end

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

    # Delegates inspection to the real data structure
    #
    # @return [String] returns a string containing a detailed stats summary
    def inspect
      data.to_s
    end
    alias :to_s :inspect

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

    # Returns struct based on stats data from response.
    #
    # @return [Beaneater::StatStruct] the stats
    # @example
    #  self.data # => { 'version' : 1.7, 'total_connections' : 23 }
    #  self.data.total_connections # => 23
    #
    def data
      StatStruct.from_hash(client.connection.transmit('stats')[:body])
    end
  end # Stats
end # Beaneater