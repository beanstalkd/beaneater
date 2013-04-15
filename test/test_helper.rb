ENV["TEST"] = 'true'
require 'rubygems'
require 'minitest/autorun'
$:.unshift File.expand_path("../../lib")
require 'beaneater'
require 'timeout'
require 'mocha'
require 'json'

class MiniTest::Unit::TestCase

  # Cleans up all jobs from tubes
  # cleanup_tubes!(['foo'], @bp)
  def cleanup_tubes!(tubes, bp=nil)
    bp ||= @pool
    tubes.each do |name|
      bp.tubes.find(name).clear
    end
  end
end