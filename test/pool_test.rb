# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Pool do

  describe 'for #new' do
    before do
      @host_string_port = 'localhost:11301'
      @host_num_port = '127.0.0.1:11302'
      @host_string = 'host.local'
      @host_num = '1.1.1.1:11303'
      @hosts = [@host_string_port, @host_num_port, @host_string, @host_num]

      Net::Telnet.expects(:new).with('Host' => 'localhost', "Port" => 11301, "Prompt" => /\n/).once
      Net::Telnet.expects(:new).with('Host' => '127.0.0.1', "Port" => 11302, "Prompt" => /\n/).once
      Net::Telnet.expects(:new).with('Host' => 'host.local', "Port" => 11300, "Prompt" => /\n/).once
      Net::Telnet.expects(:new).with('Host' => '1.1.1.1', "Port" => 11303, "Prompt" => /\n/).once

      @bp = Beaneater::Pool.new(@hosts)
    end

    it "should init 4 connections" do
      assert_equal 4, @bp.connections.size
    end
  end # new

  describe 'for #transmit_to_all' do
    before do
      @hosts = ['localhost', 'localhost']
      @bp = Beaneater::Pool.new(@hosts)
    end

    it "should return yaml loaded response" do
      res = @bp.transmit_to_all 'stats'
      assert_equal 2, res.size
      refute_nil res.first[:body]['current-connections']
    end
  end # transmit_to_all

  describe 'for #transmit_to_rand' do
    before do
      @hosts = ['localhost', 'localhost']
      @bp = Beaneater::Pool.new(@hosts)
    end

    it "should return yaml loaded response" do
      res = @bp.transmit_to_rand 'stats'
      refute_nil res[:body]['current-connections']
      assert_equal 'OK', res[:status]
    end

    it "should return id" do
      Net::Telnet.any_instance.expects(:cmd).with(has_entries('String' => 'foo')).returns('INSERTED 254')
      res = @bp.transmit_to_rand 'foo'
      assert_equal '254', res[:id]
      assert_equal 'INSERTED', res[:status]
    end
  end # transmit_to_rand

  describe 'for #transmit_until_res' do
    before do
      @hosts = ['localhost', 'localhost']
      @bp = Beaneater::Pool.new(@hosts)
      Beaneater::Connection.any_instance.expects(:transmit).with('foo', {}).twice.
      returns({:status => "FAILED", :body => 'x'}).then.
      returns({:status => "OK", :body => 'y'}).then.returns({:status => "OK", :body => 'z'})
    end

    it "should returns first matching status" do
      assert_equal 'y', @bp.transmit_until_res('foo', :status => 'OK')[:body]
    end
  end # transmit_until_res

  describe 'for #stats' do
    before do
      @hosts = ['localhost', 'localhost']
      @bp = Beaneater::Pool.new(@hosts)
    end

    it("should return stats object"){ assert_kind_of Beaneater::Stats, @bp.stats }
  end # stats

  describe 'for #tubes' do
    before do
      @hosts = ['localhost', 'localhost']
      @bp = Beaneater::Pool.new(@hosts)
    end

    it("should return Tubes object"){ assert_kind_of Beaneater::Tubes, @bp.tubes }
  end # tubes

end # Beaneater::Pool