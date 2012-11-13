# Simple ruby client for interacting with beanstalkd.
module Beaneater
  # Represents collection of beanstalkd connections.
  class Pool
    # Default number of retries to send a command to a connection
    MAX_RETRIES = 3

    # @!attribute connections
    #   @return [Array<Beaneater::Connection>] returns Collection of connections
    attr_reader :connections

    # Initialize new connection
    #
    # @param [Array<String>] addresses Array of beanstalkd server addresses
    # @example
    #   Beaneater::Pool.new(['localhost:11300', '127.0.0.1:11300'])
    #
    #   ENV['BEANSTALKD_URL'] = 'localhost:11300,127.0.0.1:11300'
    #   @bp = Beaneater::Pool.new
    #   @bp.connections.first.host # => 'localhost'
    #   @bp.connections.last.host # => '127.0.0.1'
    #
    def initialize(addresses=nil)
      addresses = addresses || host_from_env || Beaneater.configuration.beanstalkd_url
      @connections = Array(addresses).map { |a| Connection.new(a) }
    end

    # Returns Beaneater::Stats object for accessing beanstalk stats.
    #
    # @return [Beaneater::Stats] stats object
    # @api public
    def stats
      @stats ||= Stats.new(self)
    end

    # Returns Beaneater::Jobs object for accessing job related functions.
    #
    # @return [Beaneater::Jobs] jobs object
    # @api public
    def jobs
      @jobs ||= Jobs.new(self)
    end

    # Returns Beaneater::Tubes object for accessing tube related functions.
    #
    # @return [Beaneater::Tubes] tubes object
    # @api public
    def tubes
      @tubes ||= Tubes.new(self)
    end

    # Sends command to every beanstalkd server set in the pool.
    #
    # @param [String] command Beanstalkd command
    # @param [Hash{String => String, Boolean}] options telnet connections options
    # @param [Proc] block Block passed to telnet connection during transmit
    # @return [Array<Hash{String => String, Number}>] Beanstalkd command response from each instance
    # @example
    #   @pool.transmit_to_all("stats")
    #
    def transmit_to_all(command, options={}, &block)
      res_exception = nil
      res = connections.map { |conn|
        begin
          safe_transmit { conn.transmit(command, options, &block) }
        rescue UnexpectedResponse => ex # not the correct status
          res_exception = ex
          nil
        end
      }.compact
      raise res_exception if res.none? && res_exception
      res
    end

    # Send command to each beanstalkd servers until getting response expected
    #
    # @param [String] command Beanstalkd command
    # @param [Hash{String => String, Boolean}] options telnet connections options
    # @param [Proc] block Block passed in telnet connection object
    # @return [Array<Hash{String => String, Number}>] Beanstalkd command response from the instance
    # @example
    #   @pool.transmit_until_res('peek-ready', :status => "FOUND", &block)
    #
    def transmit_until_res(command, options={}, &block)
      status_expected  = options.delete(:status)
      res_exception = nil
      connections.each do |conn|
        begin
          res = safe_transmit { conn.transmit(command, options, &block) }
          return res if res[:status] == status_expected
        rescue UnexpectedResponse => ex # not the correct status
          res_exception = ex
          next
        end
      end
      raise res_exception if res_exception
    end

    # Sends command to a random beanstalkd server in the pool.
    #
    # @param [String] command Beanstalkd command
    # @param [Hash{String => String,Boolean}] options telnet connections options
    # @param [Proc] block Block passed in telnet connection object
    # @return [Array<Hash{String => String, Number}>] Beanstalkd command response from the instance
    # @example
    #   @pool.transmit_to_rand("stats", :match => /\n/)
    #
    def transmit_to_rand(command, options={}, &block)
      safe_transmit do
        conn = connections.respond_to?(:sample) ? connections.sample : connections.choice
        conn.transmit(command, options, &block)
      end
    end

    # Closes all connections within the pool.
    #
    # @example
    #  @pool.close
    #
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