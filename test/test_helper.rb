# frozen_string_literal: true

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

  # The beanstalkd binary for tests that stop and restart their own server: BEANSTALKD_BIN, or
  # `beanstalkd` on PATH. Skips the test when neither is available.
  def beanstalkd_bin
    bin = ENV['BEANSTALKD_BIN']
    return bin if bin && !bin.empty?
    on_path = ENV['PATH'].to_s.split(File::PATH_SEPARATOR).any? do |dir|
      File.executable?(File.join(dir, 'beanstalkd'))
    end
    skip("beanstalkd not found: put it on PATH or set BEANSTALKD_BIN") unless on_path
    'beanstalkd'
  end

  # A free local port for a private beanstalkd
  def free_port
    server = TCPServer.new('127.0.0.1', 0)
    server.addr[1]
  ensure
    server.close if server
  end

  # Starts a private beanstalkd on port and waits until it accepts connections.
  #
  # @return [Integer] the server's pid
  def start_beanstalkd(port)
    pid = Process.spawn(beanstalkd_bin, '-l', '127.0.0.1', '-p', port.to_s, [:out, :err] => File::NULL)
    50.times do
      begin
        TCPSocket.new('127.0.0.1', port).close
        return pid
      rescue Errno::ECONNREFUSED
        sleep 0.05
      end
    end
    stop_beanstalkd(pid)
    flunk "beanstalkd did not start on port #{port}"
  end

  # Kills a server started by start_beanstalkd
  def stop_beanstalkd(pid)
    Process.kill('KILL', pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end
end
