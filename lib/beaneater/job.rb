module Beaneater
  class Job
    # Class Methods
    class << self
      # @beaneater_connection.jobs.register('tube2', :retry_on => [Timeout::Error]) do |job|
      #  process_one(job)
      # end
      def register(tube_name, options={})

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
      alias_method :peek, :find
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