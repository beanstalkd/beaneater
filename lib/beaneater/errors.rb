module Beaneater
  class NotConnected < RuntimeError; end
  class InvalidTubeName < RuntimeError; end

  class UnexpectedResponse < RuntimeError
    ERROR_STATES = %w(OUT_OF_MEMORY INTERNAL_ERROR
      BAD_FORMAT UNKNOWN_COMMAND JOB_TOO_BIG DRAINING
      TIMED_OUT DEADLINE_SOON NOT_FOUND NOT_IGNORED EXPECTED_CRLF)

    attr_reader :status, :cmd

    def initialize(status, cmd)
      @status, @cmd = status, cmd
      super("Response failed with: #{status}")
    end

    # UnexpectedResponse.from_response('NOT_FOUND') => NotFoundError
    # UnexpectedResponse.from_response('OUT_OF_MEMORY') => OutOfMemoryError
    def self.from_status(status, cmd)
      error_klazz_name = status.split('_').map { |w| w.capitalize }.join
      error_klazz_name << "Error" unless error_klazz_name =~ /Error$/
      error_klazz = Beaneater.const_get(error_klazz_name)
      error_klazz.new(status, cmd)
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
  class NotIgnoredError < UnexpectedResponse; end
end