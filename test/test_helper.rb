ENV["TEST"] = 'true'
require 'rubygems'
require 'minitest/autorun'
$:.unshift File.expand_path("../../lib")
require 'beaneater'
require 'fakeweb'
require 'mocha'
require 'json'

FakeWeb.allow_net_connect = false

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