module Beaneater
  class Tubes < PoolCommand
    # @beaneater_connection.tubes.find('tube2')
    def find(tube_name)
      Tube.new(self.pool, tube_name)
    end

    # @beaneater_connection.tubes.reserve('tube2', 'tube3') { |job| process(job) }
    def reserve(*tube_names, &block)
      res = transmit_to_rand 'reserve'
      job = Job.new(res)
      block.call(job)
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
      transmit_to_rand('list-tubes-watched')[:body]
    end

    def used
    end

    def watch(*names)
      names.each do |t|
        transmit_to_all "watch #{t}"
      end
    end

    def watch!(*tube_names)
      ignore!(*watched)
      watch(*tube_names)
    end

    def ignore!(*names)
      names.each do |w|
        transmit_to_all "ignore #{w}"
      end
    end


  end # Tubes
end # Beaneater