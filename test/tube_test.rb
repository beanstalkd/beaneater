# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Tube do
  describe "for #put" do
    before do
      @pool = Beaneater::Pool.new(['localhost'])
      @tube = Beaneater::Tube.new(@pool, 'foo')
    end

    it "should insert a job" do
      @tube.put "bar"
      assert_equal "bar", @tube.peek(:ready).body
    end

    it "should insert a delayed job" do
      @tube.put "delayed", :delay => 1
      assert_equal "delayed", @tube.peek(:delayed).body
    end

    after do
      begin
        Timeout.timeout(1) do
          @pool.tubes.watch!('foo')
          tube = @pool.tubes.find('foo')
          if tube.peek(:delayed)
            while delayed = tube.peek(:delayed) do
              delayed.delete
            end
          else
            @pool.tubes.reserve('foo') do |job|
              job.delete
            end
          end
        end
      rescue Timeout::Error
        # nothing
      end
    end
  end #find
end # Beaneater::Tubes