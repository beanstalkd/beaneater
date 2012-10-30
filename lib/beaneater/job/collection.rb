module Beaneater
  class Jobs < PoolCommand
    class AbortProcessException < StandardError; end

    attr_reader :process_jobs

    MAX_RETRIES = 3
    RELEASE_DELAY = 1

    # @beaneater_connection.jobs.register('tube2', :retry_on => [Timeout::Error]) do |job|
    #  process_one(job)
    # end
    def register(tube_name, options={}, &block)
      @process_jobs ||= {}
      max_retries = options[:max_retries] || MAX_RETRIES
      retry_on = Array(options[:retry_on])
      @process_jobs[tube_name.to_s] = { :block => block, :retry_on => retry_on, :max_retries => max_retries }
    end

    # @beaneater_connection.jobs.process # all described tubes
    # release_delay
    def process!(options={})
      release_delay = options.delete(:release_delay) || RELEASE_DELAY
      tubes.watch!(*process_jobs.keys)
      loop do
        job = tubes.reserve
        processor = process_jobs[job.stats.tube]
        begin
          processor[:block].call job
          job.delete
        rescue AbortProcessException
          job.bury
          break
        rescue *processor[:retry_on]
          job.stats.releases >= processor[:max_retries] ? job.bury : job.release(:delay => release_delay)
        rescue
          job.bury
        end
      end
    end

    # @beaneater_connection.jobs.find(123)
    def find(id)
      res = transmit_until_res("peek #{id}", :status => "FOUND")
      Job.new(res) if res
    end
    alias_method :peek, :find
  end # Jobs
end # Beaneater