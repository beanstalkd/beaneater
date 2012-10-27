require 'net/telnet'

%w(version pool_command pool connection stats tube job).each do |f|
  require "beaneater/#{f}"
end