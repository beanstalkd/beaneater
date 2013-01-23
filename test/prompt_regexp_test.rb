# test/prompt_regexp_test.rb

require File.expand_path('../test_helper', __FILE__)
require 'socket'

describe "Reading from socket client" do
  before do
    @fake_port = 11301
    @tube_name = 'tube.to.test'

    @fake_server = Thread.start do
      server = TCPServer.new(@fake_port)
      loop do
        IO.select([server])
        client = server.accept_nonblock
        while line = client.gets
          case line
          when /list-tubes-watched/i
            client.print "OK #{7+@tube_name.size}\r\n---\n- #{@tube_name}\n\r\n"
          when /watch #{@tube_name}/i
            client.print "WATCHING 1\r\n"
          when /reserve/i
            client.print "RESERVED 17 25\r\n"
            client.print "[first part]"
            # Emulate network delay
            sleep 0.5
            client.print "[second part]\r\n"
          else
            client.print "ERROR\r\n"
          end
        end
      end
    end
  end

  it 'should reserve job with full body' do
    pool = Beaneater::Pool.new("localhost:#{@fake_port}")
    job = pool.tubes[@tube_name].reserve
    assert_equal '[first part][second part]', job.body
  end

  after do
    @fake_server.kill
  end
end
