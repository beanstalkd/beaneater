# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::PoolCommand do

  describe 'for #new' do
    before do
      @pool = stub
      @command = Beaneater::PoolCommand.new(@pool)
    end

    it "should store pool" do
      assert_equal @pool, @command.pool
    end
  end #new

  describe 'for #transmit_to_all' do
    describe 'for regular command' do
      before do
        @pool = stub(:transmit_to_all => [{ :body => "foo", :status => "OK" }])
        @command = Beaneater::PoolCommand.new(@pool)
      end

      it "can run regular command" do
        res = @command.transmit_to_all("foo")
        assert_equal "OK", res[0][:status]
        assert_equal "foo", res[0][:body]
      end
    end # regular command

    describe 'for merge command with hashes' do
      before do
        @pool = stub(:transmit_to_all => [
          { :body => { 'x' => 1, 'version' => 1.1 }, :status => "OK"},
          { :body => { 'x' => 3,'version' => 1.2 }, :status => "OK" }
        ])
        @command = Beaneater::PoolCommand.new(@pool)
      end

      it "can run merge command " do
        cmd = @command.transmit_to_all("bar", :merge => true)
        assert_equal "OK", cmd[:status]
        assert_equal 4, cmd[:body]['x']
        assert_equal Set[1.1, 1.2], cmd[:body]['version']
      end
    end # merged command

    describe 'for merge command with arrays' do
      before do
        @pool = stub(:transmit_to_all => [
          { :body => ['foo', 'bar'], :status => "OK"},
          { :body => ['foo', 'bar', 'baz'], :status => "OK" }
        ])
        @command = Beaneater::PoolCommand.new(@pool)
      end

      it "can run merge command " do
        cmd = @command.transmit_to_all("bar", :merge => true)
        assert_equal "OK", cmd[:status]
        assert_equal ['foo', 'bar', 'baz'].sort, cmd[:body].sort
      end
    end # merged command
  end # transmit_to_all

  describe 'for #method_missing' do
    describe '#transmit_to_rand' do
      before do
        @pool = stub
        @pool.expects(:transmit_to_rand).with('foo').returns('OK')
        @command = Beaneater::PoolCommand.new(@pool)
      end

      it 'delegates to connection' do
        assert_equal 'OK', @command.transmit_to_rand('foo')
      end
    end # transmit_to_rand

    describe 'invalid method' do
      before do
        @pool = stub
        @command = Beaneater::PoolCommand.new(@pool)
      end

      it 'raises no method error' do
        assert_raises(NoMethodError) { @command.foo('foo') }
      end
    end # transmit_to_rand
  end
end # Beaneater::PoolCommand