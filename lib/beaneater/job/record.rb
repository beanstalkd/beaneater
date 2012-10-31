module Beaneater
  class Job
    attr_reader :id, :body, :connection

    def initialize(res)
      @id         = res[:id]
      @body       = res[:body]
      @connection = res[:connection]
    end

    # beaneater_connection.jobs.find(123).bury(:pri => 10)
    def bury(options={})
      options = { :pri => stats.pri }.merge(options)
      connection.transmit("bury #{id} #{options[:pri]}")
    end

    # beaneater_connection.jobs.find(123).release(:pri => 10, :delay => 5)
    def release(options={})
      options = { :pri => stats.pri, :delay => stats.delay }.merge(options)
      connection.transmit("release #{id} #{options[:pri]} #{options[:delay]}")
    end

    # @beaneater_connection.jobs.find(123).delete
    def delete
      connection.transmit("delete #{id}")
    end

    # @beaneater_connection.jobs.find(123).touch
    def touch
      connection.transmit("touch #{id}")
    end

    ### Stats
    # @beaneater_connection.jobs.find(123).ttr # id, state, pro, age, ...
    def stats
      res = connection.transmit("stats-job #{id}")
      StatStruct.from_hash(res[:body])
    end

    # @beaneater_connection.jobs.find(123).kick
    def kick
      connection.transmit("kick-job #{id}")
    end

    # Returns true if the job is reserved
    def reserved?
      self.stats.state == "reserved"
    end

    # Returns if job exists
    def exists?
      !!self.stats
    rescue Beaneater::NotFoundError
      false
    end

    # Returns the name of the tube this job is in
    def tube
      self.stats && self.stats.tube
    end

    # Returns string representation of job
    def to_s
      "#<Beaneater::Job id=#{id} body=#{body.inspect}>"
    end
    alias :inspect :to_s

  end # Job
end # Beaneater