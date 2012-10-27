module Beaneater
  class Jobs < PoolCommand
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
  end # Jobs
end