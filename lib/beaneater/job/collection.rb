module Beaneater
  class AbortProcessingError < RuntimeError; end
  class Jobs < PoolCommand
    attr_reader :processors

    MAX_RETRIES = 3
    RELEASE_DELAY = 1

    # @beaneater_connection.jobs.find(123)
    def find(id)
      res = transmit_until_res("peek #{id}", :status => "FOUND")
      Job.new(res)
    rescue Beaneater::NotFoundError => ex
      nil
    end
    alias_method :peek, :find

    # @beaneater_connection.jobs.register('tube2', :retry_on => [Timeout::Error]) do |job|
    #  process_one(job)
    # end
    def register(tube_name, options={}, &block)
      @processors ||= {}
      max_retries = options[:max_retries] || MAX_RETRIES
      retry_on = Array(options[:retry_on])
      @processors[tube_name.to_s] = { :block => block, :retry_on => retry_on, :max_retries => max_retries }
    end

    # @beaneater_connection.jobs.process # all described tubes
    # release_delay
    def process!(options={})
      release_delay = options.delete(:release_delay) || RELEASE_DELAY
      tubes.watch!(*processors.keys)
      loop do
        job = tubes.reserve
        processor = processors[job.tube]
        begin
          processor[:block].call(job)
          job.delete
        rescue AbortProcessingError
          break
        rescue *processor[:retry_on]
          job.release(:delay => release_delay) if job.stats.releases < processor[:max_retries]
        rescue StandardError => e # handles unspecified errors
          job.bury
        ensure # bury if still reserved
          job.bury if job.exists? && job.reserved?
        end
      end
    end # process!
  end # Jobs
end # Beaneater