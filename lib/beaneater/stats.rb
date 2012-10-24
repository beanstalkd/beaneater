module Beaneater
  class Stats < Command
    # bs.stats['total_connections']
    def [](k)
      body[k.to_s.gsub(/_/, '-')]
    end

    def keys
      body.keys.map { |k| k.to_s.gsub(/-/, '_') }
    end

    # bs.stats.total_connections
    def method_missing(name, *args, &block)
      self[name]
    end

    protected

    def body
      cmd('stats', :merge => true)[:body]
    end
  end
end