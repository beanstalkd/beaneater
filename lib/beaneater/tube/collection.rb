module Beaneater
  class Tubes < PoolCommand
    # @beaneater_connection.tubes.find('tube2')
    def find(tube_name)
      Tube.new(self.pool, tube_name)
    end

    # @beaneater_connection.tubes.reserve { |job| process(job) }
    def reserve(&block)
      res = transmit_to_rand 'reserve'
      job = Job.new(res)
      block.call(job) if block_given?
      job
    end

    # @beaneater_connection.tubes.kick(10)
    def kick(bounds)
    end

    # @beaneater_connection.tubes.all
    def all
    end

    # @beaneater_connection.tubes.watched
    # TODO should return tube objects?
    def watched
      transmit_to_rand('list-tubes-watched')[:body]
    end

    # @beaneater_connection.tubes.used
    def used
    end

    def watch(*names)
      names.each do |t|
        transmit_to_all "watch #{t}"
      end
    end

    def watch!(*tube_names)
      old_tubes = watched.map(&:to_s) - tube_names.map(&:to_s)
      watch(*tube_names)
      ignore!(*old_tubes)
    end

    def ignore!(*names)
      names.each do |w|
        transmit_to_all "ignore #{w}"
      end
    end
  end # Tubes
end # Beaneater