# test/prompt_regexp_test.rb

require File.expand_path('../test_helper', __FILE__)
require 'socket'

describe "Prompt regexp for telnet client" do
  before do
    @fake_port = 11301
    @tube_name = 'tube.to.test'

    @fake_server = fork do 
      server = TCPServer.new(@fake_port)
      loop do
        client = server.accept
        while line = client.gets
          case line
          when /list-tubes-watched/i
            client.puts "OK 11\n---\n- #{@tube_name}\n"
          when /watch #{@tube_name}/i
            client.puts 'WATCHING 1'
          when /reserve/i
            client.puts 'RESERVED 17 17'
            client.print '[first part]'
            # Emulate network delay
            sleep 0.5
            client.puts '[second part]'
          else
            client.puts 'ERROR'
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
    Process.kill("KILL", @fake_server)
  end
end