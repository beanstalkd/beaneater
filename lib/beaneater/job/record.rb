module Beaneater
  class Job
    attr_reader :id, :body, :connection

    def initialize(res)
      @id         = res[:id]
      @body       = res[:body]
      @connection = res[:connection]
    end

    # @beaneater_connection.jobs.find(123).kick
    def kick

    end

    # @beaneater_connection.jobs.find(123).delete
    def delete
      connection.transmit("delete #{id}")
    end

    ### Stats
    # @beaneater_connection.jobs.find(123).ttr # id, state, pro, age, ...
    # TODO raise exception if job not found??
    def stats
      res = connection.transmit("stats-job #{id}")
      StatStruct.from_hash(res[:body])
    end

    # Returns string representation of job
    def to_s
      "#<Beaneater::Job body=#{body.inspect}>"
    end
    alias :inspect :to_s

  end # Job
end # Beaneater