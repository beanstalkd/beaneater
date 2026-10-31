# frozen_string_literal: true

class Beaneater
  # Raises when a beanstalkd instance is no longer accessible.
  class NotConnected < RuntimeError; end
  # Raises when beanstalkd does not answer within the configured read_timeout,
  # or a command cannot be written within write_timeout. The connection is
  # closed, since a late reply would otherwise be read as the answer to the
  # next command. Not to be confused with {TimedOutError}, which is
  # beanstalkd's own TIMED_OUT reply to reserve-with-timeout.
  class SocketTimeout < NotConnected; end
  # Added to a copy of the exception a job_parser raises for a job just reserved. The copy
  # keeps the exception's class (JSON::ParserError, say), message, backtrace and cause; #job_id
  # names the job, still reserved by this connection, so the caller can bury, release or
  # delete it.
  module JobParseFailure
    # @return [String] id of the reserved job whose body the parser rejected
    attr_accessor :job_id
  end
  # Raises when the tube name specified is invalid.
  class InvalidTubeName < RuntimeError; end
  # Raises when a job has not been reserved properly.
  class JobNotReserved < RuntimeError; end

  # Abstract class for errors that occur when a command does not complete successfully.
  class UnexpectedResponse < RuntimeError
    # Set of status states that are considered errors
    ERROR_STATES = %w(OUT_OF_MEMORY INTERNAL_ERROR
      BAD_FORMAT UNKNOWN_COMMAND JOB_TOO_BIG DRAINING
      TIMED_OUT DEADLINE_SOON NOT_FOUND NOT_IGNORED EXPECTED_CRLF)

    # @!attribute status
    #   @return [String] returns beanstalkd response status
    #   @example @ex.status # => "NOT_FOUND"
    # @!attribute cmd
    #   @return [String] returns beanstalkd request command
    #   @example @ex.cmd # => "stats-job 23"
    attr_reader :status, :cmd

    # Initialize unexpected response error
    #
    # @param [Beaneater::UnexpectedResponse] status Unexpected response object
    # @param [String] cmd Beanstalkd request command
    #
    # @example
    #   Beaneater::UnexpectedResponse.new(NotFoundError, 'bury 123')
    #
    def initialize(status, cmd)
      @status, @cmd = status, cmd
      super("Response failed with: #{status}")
    end

    # Translate beanstalkd error status to ruby Exeception
    #
    # @param [String] status Beanstalkd error status
    # @param [String] cmd Beanstalkd request command
    #
    # @return [Beaneater::UnexpectedResponse] Exception for the status provided
    # @example
    #   Beaneater::UnexpectedResponse.new('NOT_FOUND', 'bury 123')
    #
    def self.from_status(status, cmd)
      error_klazz_name = status.split('_').map { |w| w.capitalize }.join
      error_klazz_name << "Error" unless error_klazz_name =~ /Error$/
      error_klazz = Beaneater.const_get(error_klazz_name)
      error_klazz.new(status, cmd)
    end
  end

  # Raises when the beanstalkd instance runs out of memory
  class OutOfMemoryError < UnexpectedResponse; end
  # Raises when the beanstalkd instance is draining and new jobs cannot be inserted
  class DrainingError < UnexpectedResponse; end
  # Raises when the job or tube cannot be found
  class NotFoundError < UnexpectedResponse; end
  # Raises when the job reserved is going to be released within a second.
  class DeadlineSoonError < UnexpectedResponse; end
  # Raises when a beanstalkd has an internal error.
  class InternalError < UnexpectedResponse; end
  # Raises when a command was not properly formatted.
  class BadFormatError < UnexpectedResponse; end
  # Raises when a command was sent that is unknown.
  class UnknownCommandError < UnexpectedResponse; end
  # Raises when command does not have proper CRLF suffix.
  class ExpectedCrlfError < UnexpectedResponse; end
  # Raises when the body of a job was too large.
  class JobTooBigError < UnexpectedResponse; end
  # Raises when a job was attempted to be reserved but the timeout occurred.
  class TimedOutError < UnexpectedResponse; end
  # Raises when a tube could not be ignored because it is the last watched tube.
  class NotIgnoredError < UnexpectedResponse; end
end
