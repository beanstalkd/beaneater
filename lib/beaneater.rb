require 'net/telnet'
require 'thread' unless defined?(Mutex)

%w(version errors pool_command pool connection stats tube job).each do |f|
  require "beaneater/#{f}"
end

module Beaneater
  # Simple ruby client for beanstalkd.
end