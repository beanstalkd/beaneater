# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Pool do

  before do
    @hosts = ['localhost', 'localhost']
    @bp = Beaneater::Pool.new(@hosts)
  end

  describe 'for #new' do

    describe "for multiple connection" do
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
    end

    describe "for invalid connection in setup" do
      it "should raise NotConnected" do
        assert_raises(Beaneater::NotConnected) { Beaneater::Pool.new('localhost:5679') }
      end
    end

    describe "for clearing watch list" do
      it "should clear connections of tube watches" do
        @bp.tubes.watch!('foo', 'bar')
        assert_equal ['foo', 'bar'].sort, @bp.tubes.watched.map(&:name).sort
        @bp2 = Beaneater::Pool.new(@hosts)
        assert_equal ['default'], @bp2.tubes.watched.map(&:name)
      end
    end

    describe "with ENV variable set" do
      before do
        ENV['BEANSTALKD_URL'] = '0.0.0.0:11300'
      end

      it "should create 1 connection" do
        bp = Beaneater::Pool.new
        bc = bp.connections.first
        assert_equal 1, bp.connections.size
        assert_equal '0.0.0.0', bc.host
        assert_equal 11300, bc.port
      end
    end
  end # new

  describe 'for #transmit_to_all' do
    it "should return yaml loaded response" do
      res = @bp.transmit_to_all 'stats'
      assert_equal 2, res.size
      refute_nil res.first[:body]['current-connections']
    end
  end # transmit_to_all

  describe 'for #transmit_to_rand' do
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
      Beaneater::Connection.any_instance.expects(:transmit).with('foo', {}).twice.
      returns({:status => "FAILED", :body => 'x'}).then.
      returns({:status => "OK", :body => 'y'}).then.returns({:status => "OK", :body => 'z'})
    end

    it "should returns first matching status" do
      assert_equal 'y', @bp.transmit_until_res('foo', :status => 'OK')[:body]
    end
  end # transmit_until_res

  describe 'for #stats' do
    it("should return stats object"){ assert_kind_of Beaneater::Stats, @bp.stats }
  end # stats

  describe 'for #tubes' do
    it("should return Tubes object"){ assert_kind_of Beaneater::Tubes, @bp.tubes }
  end # tubes

  describe "for #safe_transmit" do
    it "should retry 3 times for temporary failed connection" do
      Net::Telnet.any_instance.expects(:cmd).raises(EOFError).then.
        raises(Errno::ECONNRESET).then.returns('INSERTED 254').times(3)
      res = @bp.transmit_to_rand 'foo'
      assert_equal '254', res[:id]
      assert_equal 'INSERTED', res[:status]
    end

    it "should retry on fail 3 times for dead connection" do
      Net::Telnet.any_instance.expects(:cmd).raises(EOFError).times(3)
      assert_raises(Beaneater::NotConnected) { @bp.transmit_to_rand 'foo' }
    end

    it 'should raise proper exception for invalid status NOT_FOUND' do
      Net::Telnet.any_instance.expects(:cmd).returns('NOT_FOUND')
      assert_raises(Beaneater::NotFoundError) { @bp.transmit_to_rand 'foo' }
    end

    it 'should raise proper exception for invalid status BAD_FORMAT' do
      Net::Telnet.any_instance.expects(:cmd).returns('BAD_FORMAT')
      assert_raises(Beaneater::BadFormatError) { @bp.transmit_to_rand 'foo' }
    end

    it 'should raise proper exception for invalid status DEADLINE_SOON' do
      Net::Telnet.any_instance.expects(:cmd).returns('DEADLINE_SOON')
      assert_raises(Beaneater::DeadlineSoonError) { @bp.transmit_to_rand 'foo' }
    end
  end

  describe "for #close" do
    it "should support closing the pool" do
      connection = @bp.connections.first
      assert_equal 2, @bp.connections.size
      assert_kind_of Beaneater::Connection, connection
      assert_kind_of Net::Telnet, connection.telnet_connection
      @bp.close
      assert_equal 0, @bp.connections.size
      assert_nil connection.telnet_connection
    end
  end # close
end # Beaneater::Pool