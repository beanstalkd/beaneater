require 'beaneater/stats/fast_struct'
require 'beaneater/stats/stat_struct'

module Beaneater
  class Stats < PoolCommand
    # Returns keys for the stats data
    def keys
      data.keys
    end

    # Returns value based on hash lookup
    def [](val)
      data[val]
    end

    # Defines a cached method for looking up data for specified key
    # Protects against infinite loops by checking stacktrace
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

    # Returns struct based on merged stats data
    def data
      StatStruct.from_hash(transmit_to_all('stats', :merge => true)[:body])
    end
  end # Stats
end # Beaneater