class Beaneater
  #
  # Borrowed from:
  # https://github.com/dolzenko/faster_open_struct/blob/master/lib/faster_open_struct.rb
  #
  # Up to 40 (!) times more memory efficient version of OpenStruct
  #
  # Differences from Ruby MRI OpenStruct:
  #
  # 1. Doesn't `dup` passed initialization hash (NOTE: only reference to hash is stored)
  #
  # 2. Doesn't convert hash keys to symbols (by default string keys are used,
  #    with fallback to symbol keys)
  #
  # 3. Creates methods on the fly on `OpenStruct` class, instead of singleton class.
  #    Uses `module_eval` with string to avoid holding scope references for every method.
  #
  # 4. Refactored, crud clean, spec covered :)
  #
  # @private
  class FasterOpenStruct
    # Undefine particularly nasty interfering methods on Ruby 1.8
    undef :type if method_defined?(:type)
    undef :id if method_defined?(:id)

    def initialize(hash = nil)
      @hash = hash || {}
      @initialized_empty = hash == nil
    end

    def method_missing(method_name_sym, *args)
      if method_name_sym.to_s[-1] == ?=
        if args.size != 1
          raise ArgumentError, "wrong number of arguments (#{args.size} for 1)", caller(1)
        end

        if self.frozen?
          raise TypeError, "can't modify frozen #{self.class}", caller(1)
        end

        __new_ostruct_member__(method_name_sym.to_s.chomp("="))
        send(method_name_sym, args[0])
      elsif args.size == 0
        __new_ostruct_member__(method_name_sym)
        send(method_name_sym)
      else
        raise NoMethodError, "undefined method `#{method_name_sym}' for #{self}", caller(1)
      end
    end

    def __new_ostruct_member__(method_name_sym)
      self.class.module_eval <<-END_EVAL, __FILE__, __LINE__ + 1
      def #{ method_name_sym }
        @hash.fetch("#{ method_name_sym }", @hash[:#{ method_name_sym }]) # read by default from string key, then try symbol
                                                                          # if string key doesn't exist
      end
      END_EVAL

      unless method_name_sym.to_s[-1] == ?? # can't define writer for predicate method
        self.class.module_eval <<-END_EVAL, __FILE__, __LINE__ + 1
        def #{ method_name_sym }=(val)
          if @hash.key?("#{ method_name_sym }") || @initialized_empty       # write by default to string key (when it is present
                                                                            # in initialization hash or initialization hash
                                                                            # wasn't provided)
            @hash["#{ method_name_sym }"] = val                             # if it doesn't exist - write to symbol key
          else
            @hash[:#{ method_name_sym }] = val
          end
        end
        END_EVAL
      end
    end

    def empty?
      @hash.empty?
    end

    #
    # Compare this object and +other+ for equality.
    #
    def ==(other)
      return false unless other.is_a?(self.class)
      @hash == other.instance_variable_get(:@hash)
    end

    #
    # Returns a string containing a detailed summary of the keys and values.
    #
    def inspect
      str = "#<#{ self.class }"
      str << " #{ @hash.map { |k, v| "#{ k }=#{ v.inspect }" }.join(", ") }" unless @hash.empty?
      str << ">"
    end
    alias :to_s :inspect
  end # FasterOpenStruct
end # Beaneater