ENV["TEST"] = 'true'
require 'rubygems'
require 'coveralls'
Coveralls.wear!
require 'minitest/autorun'
$:.unshift File.expand_path("../../lib")
require 'beaneater'
require 'timeout'
require 'mocha/setup' rescue require 'mocha'
require 'json'

class MiniTest::Unit::TestCase

  # Cleans up all jobs from tubes
  # cleanup_tubes!(['foo'], @beanstalk)
  def cleanup_tubes!(tubes, client=nil)
    client ||= @beanstalk
    tubes.each do |name|
      client.tubes.find(name).clear
    end
  end
end
