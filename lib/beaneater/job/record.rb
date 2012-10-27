module Beaneater
  class Job
    attr_reader :id, :body, :connection

    def initialize(res)
      @id         = res[:id]
      @body       = res[:body]
      @connection = res[:connection]
    end

    # Instance Methods
    # @beaneater_tube.put "data", :priority => 1000, :ttr => 10, :delay => 5
    def put(data, options={})

    end

    # @beaneater_connection.jobs.find(123).kick
    def kick

    end

    def delete
      connection.transmit("delete #{id}")
    end

    ### Stats
    # @beaneater_connection.jobs.find(123).ttr # id, state, pro, age, ...
    # TODO: define all methods dynamically based on stats response

    def stats
    end

    def to_s
      "#<Beaneater::Job body=#{body.inspect}>"
    end

    def inspect
      "#<Beaneater::Job id=#{id} body=#{body.inspect}>"
    end

  end # Job
end # Beaneater