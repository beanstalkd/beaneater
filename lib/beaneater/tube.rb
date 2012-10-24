module Beaneater
  class Tubes < Command
    # @beaneater_connection.tubes.find('tube2')
    def find(tube_name)
      Tube.new(connection, tube_name)
    end

    # @beaneater_connection.tubes.reserve('tube2', 'tube3') { |job| process(job) }
    def reserve(*tube_names)
    end

    # @beaneater_connection.tubes.kick(10)
    def kick(bounds)
    end

    #@beaneater_connection.tubes.all
    # => [<Beaneater::Tube>, <Beaneater::Tube>....]
    # @beaneater_connection.tubes.watched
    # @beaneater_connection.tubes.used
    def all
    end

    def watched
    end

    def used
    end
  end # Tubes

  class Tube < Command
    def initialize(connection, tube_name)
      @tube_name = tube_name
      super(connection)
    end

    # Instance Methods
    def put(data, options={})
    end

    # Accepts :ready, :delayed, :buried
    def peek(state)
    end

    def stats
    end

    # @beaneater_connection.tubes.find(123).pause(120)
    def pause(delay)
    end

    # @beaneater_connection.tubes.find('tube1').name # total-jobs, name ...
    # TODO: define all methods dynamically based on stats response
  end # Tube
end # Beaneater