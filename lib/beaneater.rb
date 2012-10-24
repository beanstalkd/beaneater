require 'net/telnet'

%w(version command connection stats tube job).each { |f| require "beaneater/#{f}" }

module Beaneater

end
