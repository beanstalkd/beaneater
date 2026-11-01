# frozen_string_literal: true

# test/arguments_test.rb

require File.expand_path('../test_helper', __FILE__)

describe "Command arguments" do
  before do
    @beanstalk = Beaneater.new('localhost')
  end

  # The connection's next command still gets its own reply
  def assert_in_step
    assert_equal 'USING', @beanstalk.connection.transmit('list-tube-used')[:status]
  end

  describe "tube names" do
    it "should raise InvalidTubeName for a name beanstalkd does not accept" do
      calls = {
        'use'   => ->(name) { @beanstalk.tubes.use(name) },
        'watch' => ->(name) { @beanstalk.tubes.watch(name) },
        'ignore' => ->(name) { @beanstalk.tubes.ignore(name) },
        'put'   => ->(name) { @beanstalk.tubes.find(name).put('x') },
        'peek'  => ->(name) { @beanstalk.tubes.find(name).peek(:ready) },
        'stats' => ->(name) { @beanstalk.tubes.find(name).stats },
        'pause' => ->(name) { @beanstalk.tubes.find(name).pause(0) }
      }
      ["a\r\nb", "a\nb", "a\rb", "a b", "-a", "a" * 201, "", "tubeé"].each do |name|
        calls.each do |call, block|
          assert_raises(Beaneater::InvalidTubeName, "#{call} #{name.inspect}") { block.call(name) }
          assert_in_step
        end
      end
      assert_equal ['default'], @beanstalk.tubes.watched.map(&:name)
      assert_equal 'default', @beanstalk.tubes.used.name
    end

    it "should raise InvalidTubeName when a reconnect would restore a name beanstalkd does not accept" do
      @beanstalk.connection.tubes_watched = ['default', "a\r\nb"]
      @beanstalk.connection.connection.shutdown(Socket::SHUT_RDWR) # the next command reconnects
      assert_raises(Beaneater::InvalidTubeName) { @beanstalk.tubes.used }
      @beanstalk.connection.tubes_watched = ['default']
      assert_equal 'default', @beanstalk.tubes.used.name
    end

    it "should accept every name beanstalkd does" do
      ['demo.test.foo', 'jobs(eu).mailers', 'MyApp.mailers', 'a+b/c;d$e_f-g', 'a' * 200, :symbol_tube].each do |name|
        tube = @beanstalk.tubes.find(name)
        tube.put('job')
        assert_equal name.to_s, tube.stats.name
        tube.pause(0)
        @beanstalk.tubes.watch(name)
        assert_includes @beanstalk.connection.tubes_watched, name.to_s
        assert_equal 'job', tube.peek(:ready).body
        @beanstalk.tubes.ignore(name)
      end
    end
  end # tube names

  describe "job ids" do
    before do
      @tube = @beanstalk.tubes.find('arguments')
      @id = @tube.put('job')[:id]
    end

    it "should find a job by an Integer or a String of digits" do
      assert_equal 'job', @beanstalk.jobs.find(@id.to_i).body
      assert_equal 'job', @beanstalk.jobs.find(@id.to_s).body
    end

    it "should raise ArgumentError for an id that is not a whole number" do
      ["#{@id}\r\nstats", "#{@id}\nstats", "#{@id} 1", "abc", "", nil, 1.5, :"1"].each do |id|
        assert_raises(ArgumentError, id.inspect) { @beanstalk.jobs.find(id) }
        assert_in_step
        job = Beaneater::Job.new(@beanstalk, :id => id, :status => 'RESERVED')
        [:delete, :touch, :kick, :stats, :bury, :release].each do |call|
          assert_raises(ArgumentError, "#{call} #{id.inspect}") { job.send(call) }
          assert_in_step
        end
      end
      assert_equal 'job', @beanstalk.jobs.find(@id).body
    end
  end # job ids

  describe "numbers" do
    before do
      @tube = @beanstalk.tubes.find('arguments')
    end

    it "should raise ArgumentError for a number that is not one" do
      ["1\r\nstats", "1\n", "1 2", "x", nil].each do |bad|
        [:pri, :delay, :ttr].each do |key|
          assert_raises(ArgumentError, "put #{key} #{bad.inspect}") { @tube.put('job', key => bad) }
          assert_in_step
        end
        assert_raises(ArgumentError, "pause #{bad.inspect}") { @tube.pause(bad) }
        assert_in_step
        assert_raises(ArgumentError, "kick #{bad.inspect}") { @tube.kick(bad) }
        assert_in_step
        assert_raises(ArgumentError, "reserve #{bad.inspect}") { @beanstalk.tubes.reserve(bad) } if bad
        assert_in_step

        @tube.put('job')
        job = @tube.reserve(0)
        assert_raises(ArgumentError, "release pri #{bad.inspect}") { job.release(:pri => bad, :delay => 0) }
        assert_in_step
        assert_raises(ArgumentError, "release delay #{bad.inspect}") { job.release(:pri => 1, :delay => bad) }
        assert_in_step
        assert_raises(ArgumentError, "bury pri #{bad.inspect}") { job.bury(:pri => bad) }
        assert_in_step
        job.delete
      end
      assert_nil @tube.peek(:ready)
    end

    it "should raise ArgumentError for a negative priority, delay or TTR" do
      [-1, "-1"].each do |bad|
        [:pri, :delay, :ttr].each do |key|
          assert_raises(ArgumentError, "put #{key} #{bad.inspect}") { @tube.put('stats', key => bad) }
          assert_in_step
        end
        assert_raises(ArgumentError, "pause #{bad.inspect}") { @tube.pause(bad) }
        assert_in_step

        @tube.put('job')
        job = @tube.reserve(0)
        assert_raises(ArgumentError, "release pri #{bad.inspect}") { job.release(:pri => bad, :delay => 0) }
        assert_raises(ArgumentError, "release delay #{bad.inspect}") { job.release(:pri => 1, :delay => bad) }
        assert_raises(ArgumentError, "bury pri #{bad.inspect}") { job.bury(:pri => bad) }
        assert_in_step
        job.delete
      end
      assert_nil @tube.peek(:ready)
    end

    it "should accept Integers and Strings of digits, and Floats where beanstalkd does" do
      @tube.put('job', :pri => '5', :delay => '0', :ttr => '60')
      job = @tube.reserve(0.5)
      assert_equal 5, job.stats.pri
      job.release(:pri => '6', :delay => '0')
      job = @beanstalk.tubes.reserve('0')
      job.bury(:pri => 7)
      assert_equal 1, @tube.kick(1.5)[:id].to_i
      @tube.pause('0')
    end
  end # numbers

  describe "peek states" do
    it "should raise ArgumentError for a state other than ready, delayed or buried" do
      tube = @beanstalk.tubes.find('arguments')
      tube.put('job')
      ["ready\r\nstats", "ready ", "reserved", ""].each do |state|
        assert_raises(ArgumentError, state.inspect) { tube.peek(state) }
        assert_in_step
      end
      assert_equal 'job', tube.peek('ready').body
    end
  end # peek states
end
