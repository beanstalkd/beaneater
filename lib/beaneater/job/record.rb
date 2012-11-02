module Beaneater
  class Job
    attr_reader :id, :body, :connection, :reserved

    def initialize(res)
      @id         = res[:id]
      @body       = res[:body]
      @connection = res[:connection]
      @reserved   = res[:status] == 'RESERVED'
    end

    # beaneater_connection.jobs.find(123).bury(:pri => 10)
    def bury(options={})
      options = { :pri => stats.pri }.merge(options)
      with_reserved("bury #{id} #{options[:pri]}") do
        @reserved = false
      end
    end

    # beaneater_connection.jobs.find(123).release(:pri => 10, :delay => 5)
    def release(options={})
      options = { :pri => stats.pri, :delay => stats.delay }.merge(options)
      with_reserved("release #{id} #{options[:pri]} #{options[:delay]}") do
        @reserved = false
      end
    end

    # @beaneater_connection.jobs.find(123).touch
    def touch
      with_reserved("touch #{id}")
    end

    # @beaneater_connection.jobs.find(123).delete
    def delete
      transmit("delete #{id}") { @reserved = false }
    end

    # @beaneater_connection.jobs.find(123).kick
    def kick
      transmit("kick-job #{id}")
    end

    # @beaneater_connection.jobs.find(123).ttr # id, state, pro, age, ...
    def stats
      res = transmit("stats-job #{id}")
      StatStruct.from_hash(res[:body])
    end

    # Returns true if the job is reserved
    def reserved?
      @reserved || self.stats.state == "reserved"
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

    protected

    # transmit('stats')
    # transmit('stats') { 'success' }
    def transmit(body, &block)
      res = connection.transmit(body)
      yield if block_given?
      res
    end

    # with_reserved("stats") { @reserved = false }
    def with_reserved(body, &block)
      raise JobNotReserved unless reserved?
      transmit(body, &block)
    end

  end # Job
end # Beaneater