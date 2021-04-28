ENV["TEST"] = 'true'
require 'rubygems'
require 'coveralls'
Coveralls.wear!
require 'minitest/autorun'
$:.unshift File.expand_path("../../lib")
require 'beaneater'
require 'timeout'
begin
  require 'mocha/minitest'
rescue LoadError
  require 'mocha'
end
require 'json'

class MiniTest::Unit::TestCase

  # Cleans up all jobs from specific tubes
  #
  # @example
  #   cleanup_tubes!(['foo'], @beanstalk)
  #
  def cleanup_tubes!(tubes, client=nil)
    client ||= @beanstalk
    tubes.each do |name|
      client.tubes.find(name).clear
    end
  end

  # Cleans up all jobs from all tubes known to the connection
  def flush_all(client=nil)
    client ||= @beanstalk

    # Do not continue if it is a mock or the connection has been closed
    return if !client.is_a?(Beaneater) || !client.connection.connection

    client.tubes.all.each do |tube|
      tube.clear
    end
  end

  # Run clean up after each test to ensure clean state in all tests
  def teardown
    flush_all
  end
end
