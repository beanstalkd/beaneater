module Beaneater
  class NotConnected < RuntimeError; end
  class WaitingForJobError < RuntimeError; end
  class InvalidTubeName < RuntimeError; end

  class UnexpectedResponse < RuntimeError
    ERROR_STATES = %w(OUT_OF_MEMORY INTERNAL_ERROR
      BAD_FORMAT UNKNOWN_COMMAND JOB_TOO_BIG DRAINING
      TIMED_OUT DEADLINE_SOON NOT_FOUND)

    # UnexpectedResponse.from_response('NOT_FOUND') => NotFoundError
    # UnexpectedResponse.from_response('OUT_OF_MEMORY') => OutOfMemoryError
    def self.from_response(status)
      error_klazz_name = status.split('_').map { |w| w.capitalize }.join
      error_klazz_name << "Error" unless error_klazz_name =~ /Error$/
      error_klazz = Beaneater.const_get(error_klazz_name)
      error_klazz.new(status)
    end
  end

  class OutOfMemoryError < UnexpectedResponse; end
  class DrainingError < UnexpectedResponse; end
  class NotFoundError < UnexpectedResponse; end
  class DeadlineSoonError < UnexpectedResponse; end
  class InternalError < UnexpectedResponse; end
  class BadFormatError < UnexpectedResponse; end
  class UnknownCommandError < UnexpectedResponse; end
  class ExpectedCRLFError < UnexpectedResponse; end
  class JobTooBigError < UnexpectedResponse; end
  class TimedOutError < UnexpectedResponse; end
end