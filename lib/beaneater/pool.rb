module Beaneater
  # Represents collection of connections.
  class Pool
    # Default number of retries to send a command to a connection
    MAX_RETRIES = 3

    # @!attribute connections
    #   @return [Array<Beaneater::Connection>] returns Collection of connections
    attr_reader :connections

    # Initialize new connection
    #
    # @param [Array] hosts Array of beanstalkd server host
    #
    # @example
    #   Beaneater::Pool.new(['localhost:11300', '127.0.0.1:11300'])
    #
    #   ENV['BEANSTALKD_URL'] = 'localhost:11300,127.0.0.1:11300'
    #   @bp = Beaneater::Pool.new
    #   @bp.connections.first.host # => 'localhost'
    #   @bp.connections.last.host # => '127.0.0.1'
    def initialize(hosts=nil)
      hosts = hosts || host_from_env
      @connections = Array(hosts).map { |h| Connection.new(h) }
    end

    # Returns Beaneater::Stats object
    #
    # @api public
    def stats
      @stats ||= Stats.new(self)
    end

    # Returns Beaneater::Jobs object
    #
    # @api public
    def jobs
      @jobs ||= Jobs.new(self)
    end

    # Returns Beaneater::Tubes object
    #
    # @api public
    def tubes
      @tubes ||= Tubes.new(self)
    end

    # Send command to every beanstalkd servers set in pool
    #
    # @param [String] command Beanstalkd command
    # @param [Hash] options telnet connections options
    # @param [Proc] block Block passed in telnet connection object
    #
    # @example
    #   @pool.transmit_to_all("stats")
    def transmit_to_all(command, options={}, &block)
      connections.map do |conn|
        safe_transmit { conn.transmit(command, options, &block) }
      end
    end

    # Send command to a random beanstalkd servers set in pool
    #
    # @param [String] command Beanstalkd command
    # @param [Hash] options telnet connections options
    # @param [Proc] block Block passed in telnet connection object
    #
    # @example
    #   @pool.transmit_to_rand("stats", :match => /\n/)
    def transmit_to_rand(command, options={}, &block)
      safe_transmit do
        conn = connections.respond_to?(:sample) ? connections.sample : connections.choice
        conn.transmit(command, options, &block)
      end
    end

    # Send command to each beanstalkd servers until getting response expected
    #
    # @param [String] command Beanstalkd command
    # @param [Hash] options telnet connections options
    # @param [Proc] block Block passed in telnet connection object
    #
    # @example
    #   @pool.transmit_until_res('peek-ready', :status => "FOUND", &block)
    def transmit_until_res(command, options={}, &block)
      status_expected  = options.delete(:status)
      connections.each do |conn|
        res = safe_transmit { conn.transmit(command, options, &block) }
        return res if res[:status] == status_expected
      end && nil
    end

    # Closes all connections within pool
    def close
      while @connections.any?
        conn = @connections.pop
        conn.close
      end
    end

    protected

    # Transmit command to beanstalk connections safely handling failed connections
    #
    # @param [Proc] block The command to execute.
    # @return [Object] Result of the block passed
    # @raise [Beaneater::DrainingError,Beaneater::NotConnected] Could not connect to Beanstalk client
    # @example
    #  safe_transmit { conn.transmit('foo') }
    #   # => "result of foo command from beanstalk"
    #
    def safe_transmit(&block)
      retries = 1
      begin
        yield
      rescue DrainingError, EOFError, Errno::ECONNRESET, Errno::EPIPE => ex
        # TODO remove faulty connections from pool?
        # https://github.com/kr/beanstalk-client-ruby/blob/master/lib/beanstalk-client/connection.rb#L405-410
        if retries < MAX_RETRIES
          retries += 1
          retry
        else # finished retrying, fail out
          ex.is_a?(DrainingError) ? raise(ex) : raise(NotConnected, "Could not connect!")
        end
      end
    end # transmit_call

    # The hosts provided by BEANSTALKD_URL environment variable, if available.
    #
    # @return [Array] Set of beanstalkd host addresses
    # @example
    #  ENV['BEANSTALKD_URL'] = "localhost:1212,localhost:2424"
    #   # => ['localhost:1212', 'localhost:2424']
    #
    def host_from_env
      ENV['BEANSTALKD_URL'].respond_to?(:length) && ENV['BEANSTALKD_URL'].length > 0 && ENV['BEANSTALKD_URL'].split(',').map(&:strip)
    end

  end # Pool
end # Beaneater