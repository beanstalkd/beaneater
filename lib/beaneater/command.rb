require 'set'

module Beaneater
  class Command
    attr_reader :connection

    def initialize(connection)
      @connection = connection
    end

    # cmd('use foo')
    # cmd('stats', :merge => true)
    def cmd(body, options={}, &block)
      merge = options.delete(:merge)
      res = connection.cmd(body, options, &block)
      if merge
        res = { :status => res.first[:status], :body => sum_hashes(res.map { |r| r[:body] }) }
      end
      res
    end

    protected

    def sum_hashes(hs)
      hs.inject({}){ |a,b| a.merge(b) { |k,o,n| combine_stats(k, o, n)}}
    end

    def combine_stats(k, a, b)
      ['name', 'version', 'pid'].include?(k) ? Set[a] + Set[b] : a + b
    end
  end
end