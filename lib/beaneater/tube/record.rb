module Beaneater
  class Tube < PoolCommand
    # TODO Make it configurable?
    DEFAULT_DELAY = 0
    DEFAULT_PRIORITY = 2**31 # 0 is the highest pri
    DEFAULT_TTR = 1

    attr_reader :name

    def initialize(pool, name)
      @name = name
      super(pool)
    end

    # @beaneater_tube.put "data", :pri => 1000, :ttr => 10, :delay => 5
    def put(data, options={})
      transmit_to_all "use #{@name}"
      options = { :pri => DEFAULT_PRIORITY, :delay => DEFAULT_DELAY, :ttr => DEFAULT_TTR }.merge(options)
      cmd_options = "#{options[:pri]} #{options[:delay]} #{options[:ttr]} #{data.bytesize}"
      command = "put #{cmd_options}\n#{data}"
      transmit_to_rand(command)
    end

    # Accepts :ready, :delayed, :buried
    def peek(state)
      transmit_to_all "use #{@name}"
      res = transmit_until_res "peek-#{state}", :status => "FOUND"
      Job.new(res) if res
    end

    # Reserves job from tube
    def reserve(&block)
      pool.tubes.watch!(self.name)
      pool.tubes.reserve(&block)
    end

    # Returns stats for this tube
    def stats
      res = transmit_to_all("stats-tube #{name}", :merge => true)
      StatStruct.from_hash(res[:body])
    end

    # @beaneater_connection.tubes.find(123).pause(120)
    def pause(delay)
      transmit_to_all("pause-tube #{name} #{delay}")
    end

    # @beaneater_connection.tubes.find('tube1').name # total-jobs, name ...
    # TODO: define all methods dynamically based on stats response

    def to_s
      "#<Beaneater::Tube name=#{name.inspect}>"
    end
    alias :inspect :to_s
  end # Tube
end # Beaneater