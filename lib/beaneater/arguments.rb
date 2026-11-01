# frozen_string_literal: true

class Beaneater
  # Checks the values beaneater writes into a command line, so that each one stays a single
  # argument of the form beanstalkd accepts.
  #
  # @private
  module Arguments
    # beanstalkd's tube names: 1 to 200 of these characters, not starting with a hyphen
    TUBE_NAME = %r{\A[A-Za-z0-9+/;.$_()][A-Za-z0-9\-+/;.$_()]{0,199}\z}
    # A whole number, as an Integer or a String of digits
    INTEGER = /\A-?\d+\z/
    # One that isn't negative
    UNSIGNED = /\A\d+\z/
    # The job states a tube can be peeked at
    PEEK_STATES = %w(ready delayed buried).freeze

    module_function

    # @return [String] the tube name
    # @raise [Beaneater::InvalidTubeName] name isn't a tube name beanstalkd accepts
    def tube_name(name)
      name = name.to_s
      raise InvalidTubeName, "Tube cannot be named '#{name}'" unless name.match?(TUBE_NAME)
      name
    end

    # @return [Integer, String] value, an Integer or a String of digits (a job id, a priority, a delay)
    # @raise [ArgumentError] value is anything else
    def integer(value, what)
      return value if integer?(value)
      raise ArgumentError, "#{what} must be an integer, not #{value.inspect}"
    end

    # Like {.integer}, for values beanstalkd takes only as a whole number that isn't negative (a priority,
    # a delay, a TTR): any other would fail on the server, and for put only after its body is sent.
    # @return [Integer, String] value
    # @raise [ArgumentError] value is anything else
    def unsigned(value, what)
      return value if value.is_a?(Integer) ? value >= 0 : value.is_a?(String) && value.match?(UNSIGNED)
      raise ArgumentError, "#{what} must be a whole number of at least 0, not #{value.inspect}"
    end

    # Like {.integer}, also accepting a Float, which beanstalkd reads up to the decimal point
    # where a command allows it (a reserve timeout, the number of jobs to kick).
    def number(value, what)
      return value if value.is_a?(Float) || integer?(value)
      raise ArgumentError, "#{what} must be a number, not #{value.inspect}"
    end

    def integer?(value)
      value.is_a?(Integer) || (value.is_a?(String) && value.match?(INTEGER))
    end

    # @return [String] the job state to peek at
    # @raise [ArgumentError] state isn't ready, delayed or buried
    def peek_state(state)
      state = state.to_s
      return state if PEEK_STATES.include?(state)
      raise ArgumentError, "state must be one of #{PEEK_STATES.join(', ')}, not #{state.inspect}"
    end
  end # Arguments
end # Beaneater
