require 'net/telnet'

%w(version pool_command pool connection stats tube job).each { |f| require "beaneater/#{f}" }

module Beaneater

end
