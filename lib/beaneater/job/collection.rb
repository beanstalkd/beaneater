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

    # @beaneater_connection.jobs.find(123)
    def find(id)
      res = transmit_until_res("peek #{id}", :status => "FOUND")
      Job.new(res) if res
    end
    alias_method :peek, :find
  end # Jobs
end