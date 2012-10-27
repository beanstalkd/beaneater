module Beaneater
  class Stats < PoolCommand
    KEYS = %w(current-jobs-urgent current-jobs-ready current-jobs-reserved
              current-jobs-delayed current-jobs-buried cmd-put cmd-peek
              cmd-peek-ready cmd-peek-delayed cmd-peek-buried cmd-reserve
              cmd-use cmd-watch cmd-ignore cmd-delete cmd-release cmd-bury
              cmd-kick cmd-stats cmd-stats-job cmd-stats-tube cmd-list-tubes
              cmd-list-tube-used cmd-list-tubes-watched cmd-pause-tube
              job-timeouts total-jobs max-job-size current-tubes current-connections
              current-producers current-workers current-waiting total-connections
              pid version rusage-utime rusage-stime uptime binlog-oldest-index
              binlog-current-index binlog-max-size binlog-records-written
              binlog-records-migrated)


    # bs.stats['total_connections']
    def [](k)
      body[k.to_s.gsub(/_/, '-')]
    end

    def keys
      KEYS.map { |k| k.to_s.gsub(/-/, '_') }
    end

    # bs.stats.total_connections
    def method_missing(name, *args, &block)
      if keys.include?(name.to_s)
        self[name]
      else
        super
      end
    end

    protected

    def body
      transmit_to_all('stats', :merge => true)[:body]
    end
  end
end