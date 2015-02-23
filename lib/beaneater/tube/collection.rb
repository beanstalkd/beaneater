class Beaneater
  # Represents collection of tube related commands.
  class Tubes
    # @!attribute client
    #   @return [Beaneater] returns the client instance
    attr_reader :client

    # Creates new tubes instance.
    #
    # @param [Beaneater] client The beaneater client instance.
    # @example
    #  Beaneater::Tubes.new(@client)
    #
    def initialize(client)
      @last_used = 'default'
      @client = client
    end

    # Delegates transmit to the connection object.
    #
    # @see Beaneater::Connection#transmit
    def transmit(command, options={})
      client.connection.transmit(command, options)
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
      Tube.new(client, tube_name)
    end
    alias_method :[], :find

    # Reserves a ready job looking at all watched tubes.
    #
    # @param [Integer] timeout Number of seconds before timing out.
    # @param [Proc] block Callback to perform on the reserved job.
    # @yield [job] Reserved beaneater job.
    # @return [Beaneater::Job] Reserved beaneater job.
    # @example
    #   @client.tubes.reserve { |job| process(job) }
    #     # => <Beaneater::Job id=5 body="foo">
    #
    # @api public
    def reserve(timeout=nil, &block)
      res = transmit(
        timeout ? "reserve-with-timeout #{timeout}" : 'reserve')
      job = Job.new(client, res)
      block.call(job) if block_given?
      job
    end

    # List of all known beanstalk tubes.
    #
    # @return [Array<Beaneater::Tube>] List of all beanstalk tubes.
    # @example
    #   @client.tubes.all
    #     # => [<Beaneater::Tube name="tube2">, <Beaneater::Tube name="tube3">]
    #
    # @api public
    def all
      transmit('list-tubes')[:body].map do |tube_name|
        Tube.new(client, tube_name)
      end
    end

    # List of watched beanstalk tubes.
    #
    # @return [Array<Beaneater::Tube>] List of watched beanstalk tubes.
    # @example
    #   @client.tubes.watched
    #     # => [<Beaneater::Tube name="tube2">, <Beaneater::Tube name="tube3">]
    #
    # @api public
    def watched
      transmit('list-tubes-watched')[:body].map do |tube_name|
        Tube.new(client, tube_name)
      end
    end

    # Currently used beanstalk tube.
    #
    # @return [Beaneater::Tube] Currently used beanstalk tube.
    # @example
    #   @client.tubes.used
    #     # => <Beaneater::Tube name="tube2">
    #
    # @api public
    def used
      Tube.new(client, transmit('list-tube-used')[:id])
    end

    # Add specified beanstalkd tubes as watched.
    #
    # @param [*String] names Name of tubes to watch
    # @raise [Beaneater::InvalidTubeName] Tube to watch was invalid.
    # @example
    #   @client.tubes.watch('foo', 'bar')
    #
    # @api public
    def watch(*names)
      names.each { |t| transmit "watch #{t}" }
    rescue BadFormatError => ex
      raise InvalidTubeName, "Tube in '#{ex.cmd}' is invalid!"
    end

    # Add specified beanstalkd tubes as watched and ignores all other tubes.
    #
    # @param [*String] names Name of tubes to watch
    # @raise [Beaneater::InvalidTubeName] Tube to watch was invalid.
    # @example
    #   @client.tubes.watch!('foo', 'bar')
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
    #   @client.tubes.ignore('foo', 'bar')
    #
    # @api public
    def ignore(*names)
      names.each { |w| transmit "ignore #{w}" }
    end

    # Set specified tube as used.
    #
    # @param [String] tube Tube to be used.
    # @example
    #  @conn.tubes.use("some-tube")
    #
    def use(tube)
      return tube if @last_used == tube
      transmit("use #{tube}")
      @last_used = tube
    rescue BadFormatError
      raise InvalidTubeName, "Tube cannot be named '#{tube}'"
    end
  end # Tubes
end # Beaneater
