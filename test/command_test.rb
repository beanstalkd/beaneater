# test/connection_test.rb

require File.expand_path('../test_helper', __FILE__)

describe Beaneater::Command do

  describe 'for #new' do
    before do
      @conn = stub
      @command = Beaneater::Command.new(@conn)
    end

    it "should store connection" do
      assert_equal @conn, @command.connection
    end
  end #new

  describe 'for #cmd' do
    describe 'for regular command' do
      before do
        @conn = stub(:cmd => "OK")
        @command = Beaneater::Command.new(@conn)
      end

      it "can run regular command" do
        assert_equal "OK", @command.cmd("foo")
      end
    end # regular command

    describe 'for merged command' do
      before do
        @conn = stub(:cmd => [{ :body => { 'x' => 1, 'version' => 1.1 }}, {:body => { 'x' => 3,'version' => 1.2 }}])
        @command = Beaneater::Command.new(@conn)
      end

      it "can run merge command" do
        cmd = @command.cmd("bar", :merge => true)
        assert_equal 4, cmd[:body]['x']
        assert_equal Set[1.1, 1.2], cmd[:body]['version']
      end
    end # merged command
  end #cmd
end # Beaneater::Command