ENV["TEST"] = 'true'
require 'rubygems'
require 'minitest/autorun'
$:.unshift File.expand_path("../../lib")
require 'beaneater'
require 'fakeweb'
require 'mocha'

FakeWeb.allow_net_connect = false

class MiniTest::Unit::TestCase
  def cleanup_tubes!(tubes)
    tubes.each do |t|
      begin
        Timeout.timeout(1) do
          @pool.tubes.watch!(t)
          tube = @pool.tubes.find(t)
          if tube.peek(:delayed)
            while delayed = tube.peek(:delayed) do
              delayed.delete
            end
          else
            @pool.tubes.reserve do |job|
              job.delete
            end
          end
        end
      rescue Timeout::Error
        # nothing
      end
    end
  end
end