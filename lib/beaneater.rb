require 'thread' unless defined?(Mutex)

%w(version configuration errors pool_command pool connection stats tube job).each do |f|
  require "beaneater/#{f}"
end

module Beaneater
  # Simple ruby client for beanstalkd.

  class << self
    # Yields a configuration block
    #
    # @example
    #   Beaneater.configure do |config|
    #     config.job_parser = lamda { |body| Yaml.load(body)}
    #   end
    #
    def configure(&block)
      yield(configuration) if block_given?
      configuration
    end

    # Returns the configuration options set for Backburner
    #
    # @example
    #   Beaneater.configuration.default_put_ttr => 120
    #
    def configuration
      @_configuration ||= Configuration.new
    end
  end
end # Beaneater