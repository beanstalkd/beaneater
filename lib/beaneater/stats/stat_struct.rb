module Beaneater
  # Represents a stats hash with proper underscored keys
  class StatStruct < FasterOpenStruct
    # s = StatStruct.from_hash(:foo => "bar")
    # s.foo # => 'bar'
    def self.from_hash(hash)
      return unless hash.is_a?(Hash)
      underscore_hash = hash.inject({}) { |r, (k, v)| r[k.to_s.gsub(/-/, '_')] = v; r }
      self.new(underscore_hash)
    end

    # Access values with hash notation
    # struct['key']
    def [](key)
      self.send(key.to_s)
    end

    # Returns keys stored by this struct
    def keys
      @hash.keys.map{ |k| k.to_s }
    end
  end # StatStruct
end # Beaneater