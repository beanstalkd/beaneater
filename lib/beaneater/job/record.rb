module Beaneater
  class Job
    attr_reader :id, :body, :connection

    def initialize(res)
      @id         = res[:id]
      @body       = res[:body]
      @connection = res[:connection]
    end

    # beaneater_connection.jobs.find(123).release
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
    # TODO raise exception if job not found??
    def stats
      res = connection.transmit("stats-job #{id}")
      StatStruct.from_hash(res[:body])
    end

    # @beaneater_connection.jobs.find(123).kick
    # TODO add when beanstalk 1.8 is released
    def kick
    end

    # Returns string representation of job
    def to_s
      "#<Beaneater::Job body=#{body.inspect}>"
    end
    alias :inspect :to_s

  end # Job
end # Beaneater