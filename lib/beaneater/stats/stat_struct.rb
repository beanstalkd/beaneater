# frozen_string_literal: true

class Beaneater
  # Represents a stats hash with proper underscored keys
  class StatStruct < FasterOpenStruct
    # Convert a stats hash into a struct.
    #
    # @param [Hash{String => String}] hash Hash Stats hash to convert to struct
    # @return [Beaneater::StatStruct, nil] Stats struct from hash
    # @example
    #   s = StatStruct.from_hash(:foo => "bar")
    #   s.foo # => 'bar'
    #
    def self.from_hash(hash)
      return unless hash.is_a?(Hash)
      underscore_hash = hash.inject({}) { |r, (k, v)| r[k.to_s.gsub(/-/, '_')] = v; r }
      self.new(underscore_hash)
    end

    # Access value for stat with specified key.
    #
    # Keys are stored underscored (see {.from_hash}), so hyphenated beanstalkd
    # names like "current-jobs-ready" are underscored before lookup. This also
    # avoids defining an invalid, hyphenated method name via method_missing.
    #
    # @param [String] key Key to fetch from stats.
    # @return [String, Integer] Value for specified stat key.
    # @example
    #  @stats['foo'] # => "bar"
    #  @stats['current-jobs-ready'] # => 5
    #
    def [](key)
      self.send(key.to_s.gsub(/-/, '_'))
    end

    # Returns set of keys within this struct
    #
    # @return [Array<String>] Value for specified stat key.
    # @example
    #  @stats.keys # => ['foo', 'bar', 'baz']
    #
    def keys
      @hash.keys.map { |k| k.to_s }
    end

    # Returns the initialization hash
    #
    def to_h
      @hash
    end
  end # StatStruct
end # Beaneater
