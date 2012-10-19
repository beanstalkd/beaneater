ENV["TEST"] = 'true'
require 'rubygems'
require 'minitest/autorun'
$:.unshift File.expand_path("../../lib")
require 'mygem'
require 'fakeweb'
require 'mocha'

FakeWeb.allow_net_connect = false