module Beaneater
  class Pool
    MAX_RETRIES = 3

    attr_reader :connections

    def initialize(hosts=nil)
      hosts = hosts || host_from_env
      @connections = Array(hosts).map { |h| Connection.new(h) }
    end

    def stats
      @stats ||= Stats.new(self)
    end

    def jobs
      @jobs ||= Jobs.new(self)
    end

    def tubes
      @tubes ||= Tubes.new(self)
    end

    # transmit_to_all("stats", :match => /\n/)
    def transmit_to_all(command, options={}, &block)
      connections.map do |conn|
        safe_transmit { conn.transmit(command, options, &block) }
      end
    end

    # transmit_to_rand("stats", :match => /\n/)
    def transmit_to_rand(command, options={}, &block)
      safe_transmit do
        conn = connections.respond_to?(:sample) ? connections.sample : connections.choice
        conn.transmit(command, options, &block)
      end
    end

    # transmit_until_res('peek-ready', :status => "FOUND", &block)
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