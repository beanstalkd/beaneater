module Beaneater
  # Represents collection of tube related commands.
  class Tubes < PoolCommand

    # Creates new tubes instance.
    #
    # @param [Beaneater::Pool] pool The beaneater pool for this tube.
    # @example
    #  Beaneater::Tubes.new(@pool)
    #
    def initialize(pool)
      @last_used = 'default'
      super
    end

    # Finds the specified beanstalk tube.
    #
    # @param [String] tube_name Name of the beanstalkd tube
    # @return [Beaneater::Tube] specified tube
    # @example
    #   @pool.tubes.find('tube2')
    #   @pool.tubes['tube2']
    #     # => <Beaneater::Tube name="tube2">
    #
    # @api public
    def find(tube_name)
      Tube.new(self.pool, tube_name)
    end
    alias_method :[], :find

    # Reserves a ready job looking at all watched tubes.
    #
    # @param [Integer] timeout Number of seconds before timing out.
    # @param [Proc] block Callback to perform on the reserved job.
    # @yield [job] Reserved beaneater job.
    # @return [Beaneater::Job] Reserved beaneater job.
    # @example
    #   @conn.tubes.reserve { |job| process(job) }
    #     # => <Beaneater::Job id=5 body="foo">
    #
    # @api public
    def reserve(timeout=nil, &block)
      res = transmit_to_rand(timeout ? "reserve-with-timeout #{timeout}" : 'reserve')
      job = Job.new(res)
      block.call(job) if block_given?
      job
    end

    # List of all known beanstalk tubes.
    #
    # @return [Array<Beaneater::Tube>] List of all beanstalk tubes.
    # @example
    #   @pool.tubes.all
    #     # => [<Beaneater::Tube name="tube2">, <Beaneater::Tube name="tube3">]
    #
    # @api public
    def all
      transmit_to_all('list-tubes', :merge => true)[:body].map { |tube_name| Tube.new(self.pool, tube_name) }
    end

    # List of watched beanstalk tubes.
    #
    # @return [Array<Beaneater::Tube>] List of watched beanstalk tubes.
    # @example
    #   @pool.tubes.watched
    #     # => [<Beaneater::Tube name="tube2">, <Beaneater::Tube name="tube3">]
    #
    # @api public
    def watched
      transmit_to_all('list-tubes-watched', :merge => true)[:body].map { |tube_name| Tube.new(self.pool, tube_name) }
    end

    # Currently used beanstalk tube.
    #
    # @return [Beaneater::Tube] Currently used beanstalk tube.
    # @example
    #   @pool.tubes.used
    #     # => <Beaneater::Tube name="tube2">
    #
    # @api public
    def used
      Tube.new(self.pool, transmit_to_rand('list-tube-used')[:id])
    end

    # Add specified beanstalkd tubes as watched.
    #
    # @param [*String] names Name of tubes to watch
    # @raise [Beaneater::InvalidTubeName] Tube to watch was invalid.
    # @example
    #   @pool.tubes.watch('foo', 'bar')
    #
    # @api public
    def watch(*names)
      names.each do |t|
        transmit_to_all "watch #{t}"
      end
    rescue BadFormatError => ex
      raise InvalidTubeName, "Tube in '#{ex.cmd}' is invalid!"
    end

    # Add specified beanstalkd tubes as watched and ignores all other tubes.
    #
    # @param [*String] names Name of tubes to watch
    # @raise [Beaneater::InvalidTubeName] Tube to watch was invalid.
    # @example
    #   @pool.tubes.watch!('foo', 'bar')
    #
    # @api public
    def watch!(*names)
      old_tubes = watched.map(&:name) - names.map(&:to_s)
      watch(*names)
      ignore(*old_tubes)
    end

    # Ignores specified beanstalkd tubes.
    #
    # @param [*String] names Name of tubes to ignore
    # @example
    #   @pool.tubes.ignore('foo', 'bar')
    #
    # @api public
    def ignore(*names)
      names.each do |w|
        transmit_to_all "ignore #{w}"
      end
    end

    # Set specified tube as used.
    #
    # @param [String] tube Tube to be used.
    # @example
    #  @conn.tubes.use("some-tube")
    #
    def use(tube)
      return tube if @last_used == tube
      res = transmit_to_all("use #{tube}")
      @last_used = tube
    rescue BadFormatError
      raise InvalidTubeName, "Tube cannot be named '#{tube}'"
    end
  end # Tubes
end # Beaneater