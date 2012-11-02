module Beaneater
  # Represents job related commands.
  class Job

    # @!attribute id
    #   @return [Integer] id for the job.
    # @!attribute body
    #   @return [String] the job's body.
    # @!attribute connection
    #   @return [Beaneater::Connection] connection which has retrieved job.
    # @!attribute reserved
    #   @return [Boolean] whether the job has been reserved.
    attr_reader :id, :body, :connection, :reserved


    # Initializes a new job object.
    #
    # @param [Hash{Symbol => String,Number}] res Result from beanstalkd response
    #
    def initialize(res)
      @id         = res[:id]
      @body       = res[:body]
      @connection = res[:connection]
      @reserved   = res[:status] == 'RESERVED'
    end

    # Sends command to bury a reserved job.
    #
    # @param [Hash{Symbol => Integer}] options Settings to bury job
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

    # Sends command to release a job back to ready state.
    #
    # @param [Hash{String => Integer}] options Settings to release job
    # @option options [Integer] pri Assign new priority to job
    # @option options [Integer] delay Assign new delay to job
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

    # Sends command to touch job which extends the ttr.
    #
    # @example
    #   @beaneater_connection.jobs.find(123).touch
    #
    # @api public
    def touch
      with_reserved("touch #{id}")
    end

    # Sends command to delete a job.
    #
    # @example
    #   @beaneater_connection.jobs.find(123).delete
    #
    # @api public
    def delete
      transmit("delete #{id}") { @reserved = false }
    end

    # Sends command to kick a buried job.
    #
    # @example
    #   @beaneater_connection.jobs.find(123).kick
    #
    # @api public
    def kick
      transmit("kick-job #{id}")
    end

    # Sends command to get stats about job.
    #
    # @return [Beaneater::StatStruct] struct filled with relevant job stats
    # @example
    #   @beaneater_connection.jobs.find(123).stats
    #   @job.stats.tube # => "some-tube"
    #
    # @api public
    def stats
      res = transmit("stats-job #{id}")
      StatStruct.from_hash(res[:body])
    end

    # Check if job is currently in a reserved state.
    #
    # @return [Boolean] Returns true if the job is in a reserved state
    # @example
    #   @beaneater_connection.jobs.find(123).reserved?
    #
    # @api public
    def reserved?
      @reserved || self.stats.state == "reserved"
    end

    # Check if the job still exists.
    #
    # @return [Boolean] Returns true if the job still exists
    # @example
    #   @beaneater_connection.jobs.find(123).exists?
    #
    # @api public
    def exists?
      !self.stats.nil?
    rescue Beaneater::NotFoundError
      false
    end

    # Returns the name of the tube this job is in
    #
    # @return [String] The name of the tube for this job
    # @example
    #   @beaneater_connection.jobs.find(123).tube
    #     # => "some-tube"
    #
    def tube
      self.stats && self.stats.tube
    end

    # Returns string representation of job
    #
    # @return [String] string representation
    # @example
    #   @beaneater_connection.jobs.find(123).to_s
    #   @beaneater_connection.jobs.find(123).inspect
    #
    def to_s
      "#<Beaneater::Job id=#{id} body=#{body.inspect}>"
    end
    alias :inspect :to_s

    protected

    # Transmit command to beanstalkd instances and fetch response.
    #
    # @param [String] cmd Beanstalkd command to send.
    # @return [Hash{Symbol => String,Number}] Beanstalkd response for the command.
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
    # @return [Hash{Symbol => String,Number}] Beanstalkd response for the command.
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