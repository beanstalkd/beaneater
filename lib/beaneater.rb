require 'thread' unless defined?(Mutex)

%w(version configuration errors connection tube job stats).each do |f|
  require "beaneater/#{f}"
end

class Beaneater

  # @!attribute connection
  #   @return <Beaneater::Connection> returns the associated connection object
  attr_reader :connection

  # Initialize new instance of Beaneater
  #
  # @param [String] address in the form "host:port"
  # @example
  #   Beaneater.new('127.0.0.1:11300')
  #
  #   ENV['BEANSTALKD_URL'] = '127.0.0.1:11300'
  #   @b = Beaneater.new
  #   @b.connection.host # => '127.0.0.1'
  #   @b.connection.port # => '11300'
  #
  def initialize(address)
    @connection =  Connection.new(address)
  end

  # Returns Beaneater::Tubes object for accessing tube related functions.
  #
  # @return [Beaneater::Tubes] tubes object
  # @api public
  def tubes
    @tubes ||= Beaneater::Tubes.new(self)
  end

  # Returns Beaneater::Jobs object for accessing job related functions.
  #
  # @return [Beaneater::Jobs] jobs object
  # @api public
  def jobs
    @jobs ||= Beaneater::Jobs.new(self)
  end

  # Returns Beaneater::Stats object for accessing beanstalk stats.
  #
  # @return [Beaneater::Stats] stats object
  # @api public
  def stats
    @stats ||= Stats.new(self)
  end

  # Closes the related connection
  #
  # @example
  #  @beaneater_instance.close
  #
  def close
    connection.close if connection
  end

  protected

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