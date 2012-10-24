require 'net/telnet'

%w(version connection stats tube job).each { |f| require "beaneater/#{f}" }

module Beaneater

end
