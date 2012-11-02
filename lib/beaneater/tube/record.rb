module Beaneater
  # Beanstalk tube which contains jobs which can be inserted, reserved, et al.
  class Tube < PoolCommand
    # The default delay for inserted jobs.
    DEFAULT_DELAY = 0
    # Default priority for inserted jobs, 0 is the highest.
    DEFAULT_PRIORITY = 65536
    # Default time to respond for inserted jobs.
    DEFAULT_TTR = 120

    # @!attribute name
    #   @return [String] name of the tube
    attr_reader :name

    # Fetches the specified tube.
    #
    # @param [Beaneater::Pool] pool The beaneater pool for this tube.
    # @param [String] name The name for this tube.
    # @example
    #  Beaneater::Tube.new(@pool, 'tube-name')
    #
    def initialize(pool, name)
      @name = name.to_s
      @mutex = Mutex.new
      super(pool)
    end

    # Inserts job with specified body onto tube.
    #
    # @param [String] body The data to store with this job.
    # @param [Hash{String => Integer}] options The settings associated with this job.
    # @option options [Integer] pri priority for this job
    # @option options [Integer] ttr time to respond for this job
    # @option options [Integer] delay delay for this job
    # @return [Hash{String => String, Number}] beanstalkd command response
    # @example
    #   @tube.put "data", :pri => 1000, :ttr => 10, :delay => 5
    #
    # @api public
    def put(body, options={})
      safe_use do
        options = { :pri => DEFAULT_PRIORITY, :delay => DEFAULT_DELAY, :ttr => DEFAULT_TTR }.merge(options)
        cmd_options = "#{options[:pri]} #{options[:delay]} #{options[:ttr]} #{body.bytesize}"
        transmit_to_rand("put #{cmd_options}\n#{body}")
      end
    end

    # Peek at next job within this tube in given `state`.
    #
    # @param [String] state The job state to peek at (`ready`, `buried`, `delayed`)
    # @return [Beaneater::Job] The next job within this tube.
    # @example
    #  @tube.peek(:ready) # => <Beaneater::Job id=5 body=foo>
    #
    # @api public
    def peek(state)
      safe_use do
        res = transmit_until_res "peek-#{state}", :status => "FOUND"
        Job.new(res)
      end
    rescue Beaneater::NotFoundError => ex
      # Return nil if not found
    end

    # Reserves the next job from tube.
    #
    # @param [Integer] timeout Number of seconds before timing out
    # @param [Proc] block Callback to perform on reserved job
    # @yield [job] Job that was reserved.
    # @return [Beaneater::Job] Job that was reserved.
    # @example
    #  @tube.reserve # => <Beaneater::Job id=5 body=foo>
    #
    # @api public
    def reserve(timeout=nil, &block)
      pool.tubes.watch!(self.name)
      pool.tubes.reserve(timeout, &block)
    end

    # Kick specified number of jobs from buried to ready state.
    #
    # @param [Integer] bounds The number of jobs to kick.
    # @return [Hash{String => String, Number}] Beanstalkd command response
    # @example
    #   @tube.kick(5)
    #
    # @api public
    def kick(bounds=1)
      safe_use { transmit_to_rand("kick #{bounds}") }
    end

    # Returns related stats for this tube.
    #
    # @return [Beaneater::StatStruct] Struct of tube related values
    # @example
    #  @tube.stats.delayed # => 24
    #
    # @api public
    def stats
      res = transmit_to_all("stats-tube #{name}", :merge => true)
      StatStruct.from_hash(res[:body])
    end

    # Pause the execution of this tube for specified `delay`.
    #
    # @param [Integer] delay Number of seconds to delay tube execution
    # @return [Array<Hash{String => String, Number}>] Beanstalkd command response
    # @example
    #   @tube.pause(10)
    #
    # @api public
    def pause(delay)
      transmit_to_all("pause-tube #{name} #{delay}")
    end

    # Clears all unreserved jobs in all states from the tube
    #
    # @example
    #   @tube.clear
    #
    def clear
      pool.tubes.watch!(self.name)
      %w(delayed buried ready).each do |state|
        while job = self.peek(state.to_sym)
          job.delete
        end
      end
      pool.tubes.ignore(name)
    rescue Beaneater::UnexpectedResponse
      # swallow any issues
    end

    # String representation of tube.
    #
    # @return [String] Representation of tube including name.
    # @example
    #  @tube.to_s # => "#<Beaneater::Tube name=foo>"
    #
    def to_s
      "#<Beaneater::Tube name=#{name.inspect}>"
    end
    alias :inspect :to_s

    protected

    # Transmits a beanstalk command that requires this tube to be set as used.
    #
    # @param [Proc] block Beanstalk command to transmit.
    # @return [Object] Result of block passed
    # @example
    #  safe_use { transmit_to_rand("kick 1") }
    #    # => "Response to kick command"
    #
    def safe_use(&block)
      @mutex.lock
      tubes.use(self.name)
      yield
    ensure
      @mutex.unlock
    end
  end # Tube
end # Beaneater
