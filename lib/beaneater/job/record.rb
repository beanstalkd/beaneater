module Beaneater
  class Job

    # @!attribute id
    #   @return [Integer] returns Job id
    # @!attribute body
    #   @return [String] returns Job body
    # @!attribute connection
    #   @return [Beaneater::Connection] returns Connection which has retrieved job
    # @!attribute reserved
    #   @return [Boolean] returns If job is being reserved
    attr_reader :id, :body, :connection, :reserved


    # Initialize new connection
    #
    # @param [Hash] res result from beanstalkd response
    def initialize(res)
      @id         = res[:id]
      @body       = res[:body]
      @connection = res[:connection]
      @reserved   = res[:status] == 'RESERVED'
    end

    # Send command to bury job
    #
    # @param [Hash] options Settings to bury job
    # @option options [Integer] pri Assign new priority to job
    #
    # @example
    #   @beaneater_connection.bury({:pri => 100})
    #
    # @api public
    def bury(options={})
      options = { :pri => stats.pri }.merge(options)
      with_reserved("bury #{id} #{options[:pri]}") do
        @reserved = false
      end
    end

    # Send command to release job
    #
    # @param [Hash] options Settings to release job
    # @option options [Integer] pri Assign new priority to job
    # @option options [Integer] pri Assign new delay to job
    #
    # @example
    #   @beaneater_connection.jobs.find(123).release(:pri => 10, :delay => 5)
    #
    # @api public
    def release(options={})
      options = { :pri => stats.pri, :delay => stats.delay }.merge(options)
      with_reserved("release #{id} #{options[:pri]} #{options[:delay]}") do
        @reserved = false
      end
    end

    # Send command to touch job
    #
    # @example
    #   @beaneater_connection.jobs.find(123).touch
    #
    # @api public
    def touch
      with_reserved("touch #{id}")
    end

    # Send command to delete job
    #
    # @example
    #   @beaneater_connection.jobs.find(123).delete
    #
    # @api public
    def delete
      transmit("delete #{id}") { @reserved = false }
    end

    # Send command to kick job
    #
    # @example
    #   @beaneater_connection.jobs.find(123).kick
    #
    # @api public
    def kick
      transmit("kick-job #{id}")
    end

    # Send command to get stats about job
    #
    # @example
    #   @beaneater_connection.jobs.find(123).stats
    #
    # @api public
    def stats
      res = transmit("stats-job #{id}")
      StatStruct.from_hash(res[:body])
    end

    # Check if job is being reserved
    #
    # @example
    #   @beaneater_connection.jobs.find(123).reserved?
    #
    # @api public
    def reserved?
      @reserved || self.stats.state == "reserved"
    end

    # Check if job exists
    #
    # @example
    #   @beaneater_connection.jobs.find(123).exists?
    #
    # @api public
    def exists?
      !!self.stats
    rescue Beaneater::NotFoundError
      false
    end

    # Returns the name of the tube this job is in
    #
    # @example
    #   @beaneater_connection.jobs.find(123).tube
    #
    # @api public
    def tube
      self.stats && self.stats.tube
    end

    # Returns string representation of job
    #
    # @example
    #   @beaneater_connection.jobs.find(123).to_s
    #   @beaneater_connection.jobs.find(123).inspect
    #
    # @api public
    def to_s
      "#<Beaneater::Job id=#{id} body=#{body.inspect}>"
    end
    alias :inspect :to_s

    protected

    # Transmit command to beanstalkd instances and fetch response.
    #
    # @param [String] cmd Beanstalkd command to send.
    # @return [Hash] Beanstalkd response for the command.
    # @example
    #  transmit('stats')
    #  transmit('stats') { 'success' }
    #
    def transmit(cmd, &block)
      res = connection.transmit(cmd)
      yield if block_given?
      res
    end

    # Transmits a command which requires the job to be reserved.
    #
    # @param [String] cmd Beanstalkd command to send.
    # @return [Hash] Beanstalkd response for the command.
    # @raise [Beaneater::JobNotReserved] Command cannot execute since job is not reserved.
    # @example
    #   with_reserved("bury 26") { @reserved = false }
    #
    def with_reserved(cmd, &block)
      raise JobNotReserved unless reserved?
      transmit(cmd, &block)
    end

  end # Job
end # Beaneater