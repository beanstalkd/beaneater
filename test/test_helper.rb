ENV["TEST"] = 'true'
require 'rubygems'
require 'minitest/autorun'
$:.unshift File.expand_path("../../lib")
require 'beaneater'
require 'fakeweb'
require 'mocha'

FakeWeb.allow_net_connect = false

class MiniTest::Unit::TestCase

  # Cleans up all jobs from tubes
  # cleanup_tubes!(['foo'], @bp)
  def cleanup_tubes!(tubes, bp=nil)
    bp ||= @pool
    tubes.each do |name|
      bp.tubes.watch!(name)
      tube = bp.tubes.find(name)
      %w(delayed buried ready).each do |state|
        while job = tube.peek(state.to_sym)
          job.delete
        end
      end
      bp.tubes.ignore!(name)
    end
  end
end