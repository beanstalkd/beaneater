module Beaneater
  class AbortProcessingError < RuntimeError; end
  class Jobs < PoolCommand

    # @!attribute processors
    #   @return [Array<Proc>] returns Collection of proc to handle beanstalkd jobs
    attr_reader :processors

    # Number of retries to process a job
    MAX_RETRIES = 3

    # Delay in seconds before to make job ready again
    RELEASE_DELAY = 1

    # Peek (or find) a job across all beanstalkd servers from pool
    #
    # @param [Integer] id Job id
    #
    # @raise [Beaneater::NotFoundError] Job not found
    #
    # @example
    #   @beaneater_pool.jobs.find(123) # => <Beaneater::Job>
    #   @beaneater_pool.jobs.peek(123) # => <Beaneater::Job>
    #   @beaneater_pool.jobs.find[123] # => <Beaneater::Job>
    #
    # @api public
    def find(id)
      res = transmit_until_res("peek #{id}", :status => "FOUND")
      Job.new(res)
    rescue Beaneater::NotFoundError => ex
      nil
    end
    alias_method :peek, :find
    alias_method :[], :find

    # Add processor to handle beanstalkd job
    #
    # @param [String] tube_name Tube name
    # @param [Hash] options settings for processor
    # @option options [Integer] max_retries Number of retries to process a job
    # @option options [Array<RuntimeError>] retry_on Collection of errors to rescue and re-run processor
    # @param [Proc] block Process beanstalkd job
    #
    # @example
    #   @beanstalk.jobs.register('some-tube', :retry_on => [SomeError]) do |job|
    #     do_something(job)
    #   end
    #
    #   @beanstalk.jobs.register('other-tube') do |job|
    #     do_something_else(job)
    #   end
    #
    # @api public
    def register(tube_name, options={}, &block)
      @processors ||= {}
      max_retries = options[:max_retries] || MAX_RETRIES
      retry_on = Array(options[:retry_on])
      @processors[tube_name.to_s] = { :block => block, :retry_on => retry_on, :max_retries => max_retries }
    end

    # Watch, reserve, process and delete or bury or release jobs
    #
    # @param [Hash] options Settings for processing
    # @option options [Integer] Delay in seconds before to make job ready again
    #
    # @api public
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