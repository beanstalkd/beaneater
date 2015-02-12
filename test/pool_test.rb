# test/pool_test.rb

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

        TCPSocket.expects(:new).with('localhost',11301).once
        TCPSocket.expects(:new).with('127.0.0.1',11302).once
        TCPSocket.expects(:new).with('host.local',11300).once
        TCPSocket.expects(:new).with('1.1.1.1',11303).once

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

    it "raises UnexpectedException when any Exception occurs inside the block" do
      invalid_command = nil
      assert_raises(Beaneater::UnknownCommandError) { @bp.transmit_to_rand(invalid_command) }
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
        ENV['BEANSTALKD_URL'] = '0.0.0.0:11300,127.0.0.1:11300'
      end

      it "should create 1 connection" do
        bp = Beaneater::Pool.new
        bc = bp.connections.first
        bc2 = bp.connections.last

        assert_equal 2, bp.connections.size
        assert_equal '0.0.0.0', bc.host
        assert_equal 11300, bc.port

        assert_equal '127.0.0.1', bc2.host
        assert_equal 11300, bc2.port
      end

      after do
        ENV['BEANSTALKD_URL'] = nil
      end
    end

    describe "by configuring via Beaneater.configure" do
      before do
        Beaneater.configure.beanstalkd_url = ['0.0.0.0:11300', '127.0.0.1:11300']
      end

      it "should create 1 connection" do
        bp = Beaneater::Pool.new
        bc = bp.connections.first
        bc2 = bp.connections.last

        assert_equal 2, bp.connections.size
        assert_equal '0.0.0.0', bc.host
        assert_equal 11300, bc.port

        assert_equal '127.0.0.1', bc2.host
        assert_equal 11300, bc2.port
      end

      after do
        Beaneater.configure.beanstalkd_url = ['0.0.0.0:11300']
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
      Beaneater::Connection.any_instance.expects(:transmit).with("foo",{}).returns({:id => "254", :status => "INSERTED"})
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
    it "should retry 3 times for temporary failed connection with Errno::ECONNRESET" do
      TCPSocket.any_instance.expects(:write).times(3)
      TCPSocket.any_instance.expects(:readline).raises(Errno::ECONNRESET).then.
        raises(Errno::ECONNRESET).then.returns('INSERTED 254').times(3)
      res = @bp.transmit_to_rand "put 0 0 10 2\r\nxy"
      assert_equal '254', res[:id]
      assert_equal 'INSERTED', res[:status]
    end

    it "removes the connection with Beaneater::NotConnected" do
      first_connection = @bp.connections.first
      connections_count = @bp.connections.count
      first_connection.stubs(:transmit).
        raises(Beaneater::NotConnected.new(first_connection))

      assert_raises(Beaneater::NotConnected) do
        @bp.transmit_to_all "puts 0 0 10 2 \r\nxy"
      end
      assert_equal @bp.connections.count, connections_count - 1
    end

    it "should retry 3 times for temporary failed connection with EOFError" do
      TCPSocket.any_instance.expects(:write).times(3)
      TCPSocket.any_instance.expects(:readline).raises(EOFError).then.
        raises(EOFError).then.returns('INSERTED 254').times(3)
      res = @bp.transmit_to_rand "put 0 0 10 2\r\nxy"
      assert_equal '254', res[:id]
      assert_equal 'INSERTED', res[:status]
    end

    it "should retry 3 times for temporary failed connection with Errno::EPIPE" do
      TCPSocket.any_instance.expects(:write).times(3)
      TCPSocket.any_instance.expects(:readline).raises(Errno::EPIPE).then.
        raises(Errno::EPIPE).then.returns('INSERTED 254').times(3)
      res = @bp.transmit_to_rand "put 0 0 10 2\r\nxy"
      assert_equal '254', res[:id]
      assert_equal 'INSERTED', res[:status]
    end

    it "should retry 3 times for temporary failed connection with DrainingError" do
      ex = Beaneater::DrainingError.new('DRAINING', "foo")
      TCPSocket.any_instance.expects(:write).times(3)
      TCPSocket.any_instance.expects(:readline).raises(ex).then.
        raises(ex).then.returns('INSERTED 254').times(3)
      res = @bp.transmit_to_rand "put 0 0 10 2\r\nxy"
      assert_equal '254', res[:id]
      assert_equal 'INSERTED', res[:status]
    end

    it "should raise proper exception after max retries" do
      TCPSocket.any_instance.expects(:write).times(3)
      TCPSocket.any_instance.expects(:readline).raises(EOFError).then.
        raises(EOFError).then.raises(EOFError).times(3)
      assert_raises(Beaneater::NotConnected) do
        @bp.transmit_to_rand "put 0 0 10 2\r\nxy"
      end
    end

    it "should raise DrainingError exception after getting the error for more than max retries times" do
      ex = Beaneater::DrainingError.new('DRAINING', "foo")
      TCPSocket.any_instance.expects(:write).times(3)
      TCPSocket.any_instance.expects(:readline).raises(ex).then.
        raises(ex).then.raises(ex).times(3)
      assert_raises(Beaneater::DrainingError) do
        @bp.transmit_to_rand "put 0 0 10 2\r\nxy"
      end
    end

    it 'should raise proper exception for invalid status NOT_FOUND' do
      TCPSocket.any_instance.expects(:write).once
      TCPSocket.any_instance.expects(:readline).returns('NOT_FOUND')
      assert_raises(Beaneater::NotFoundError) { @bp.transmit_to_rand 'foo' }
    end

    it 'should raise proper exception for invalid status BAD_FORMAT' do
      TCPSocket.any_instance.expects(:write).once
      TCPSocket.any_instance.expects(:readline).returns('BAD_FORMAT')
      assert_raises(Beaneater::BadFormatError) { @bp.transmit_to_rand 'foo' }
    end

    it 'should raise proper exception for invalid status DEADLINE_SOON' do
      TCPSocket.any_instance.expects(:write).once
      TCPSocket.any_instance.expects(:readline).once.returns('DEADLINE_SOON')
      assert_raises(Beaneater::DeadlineSoonError) { @bp.transmit_to_rand 'expecting deadline' }
    end
  end # safe_transmit

  describe "for #close" do
    it "should support closing the pool" do
      connection = @bp.connections.first
      assert_equal 2, @bp.connections.size
      assert_kind_of Beaneater::Connection, connection
      assert_kind_of TCPSocket, connection.connection
      @bp.close
      assert_equal 0, @bp.connections.size
      assert_nil connection.connection
    end
  end # close
end # Beaneater::Pool
