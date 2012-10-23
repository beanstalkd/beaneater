module Beaneater
  class Job
    # Class Methods
    class << self
      # @beaneater_connection.jobs.register('tube2', :retry_on => [Timeout::Error]) do |job|
      #  process_one(job)
      # end
      def register(tube_name, options={})
        raise "Tube name is too short, it should be more than 200 bytes" if tube_name.bytes.to_a.inject(:+) < 200
        @telnet_connections.each do |connect|
          connect.cmd("watch #{tube_name}") { |c| print c }
        end
      end

      # @beaneater_connection.jobs.process # all described tubes
      # watch all described tubes
      # ignore all other tubes
      # loop do
      # reserve
      # invoke describe block based on tube
      # success => delete, fail => bury
      def process!

      end

      def find(id)

      end
      alias_method :find, :peek
    end

    # Instance Methods
    # @beaneater_tube.put "data", :priority => 1000, :ttr => 10, :delay => 5
    def put(data, options={})

    end

    # @beaneater_connection.jobs.find(123).kick
    def kick

    end

    ### Stats
    # @beaneater_connection.jobs.find(123).ttr # id, state, pro, age, ...
    # TODO: define all methods dynamically based on stats response

    def stats

    end

  end
end