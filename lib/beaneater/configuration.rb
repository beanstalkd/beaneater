# frozen_string_literal: true

class Beaneater
  class Configuration
    attr_accessor :default_put_delay   # default delay value to put a job
    attr_accessor :default_put_pri     # default priority value to put a job
    attr_accessor :default_put_ttr     # default ttr value to put a job
    attr_accessor :job_parser          # default job_parser to parse job body
    attr_accessor :job_serializer      # default serializer for job body
    attr_accessor :beanstalkd_url      # default beanstalkd url
    attr_accessor :connect_timeout     # TCP connect timeout in seconds
    attr_accessor :resolv_timeout      # DNS resolve timeout in seconds
    attr_accessor :read_timeout        # seconds to wait for a reply (added to reserve-with-timeout's own timeout; plain reserve is never cut off)
    attr_accessor :write_timeout       # seconds to wait for a command to be written

    def initialize
      @default_put_delay   = 0
      @default_put_pri     = 65536
      @default_put_ttr     = 120
      @job_parser          = lambda { |body| body }
      @job_serializer      = lambda { |body| body }
      @beanstalkd_url      = nil
      @connect_timeout     = nil
      @resolv_timeout      = nil
      @read_timeout        = nil
      @write_timeout       = nil
    end
  end # Configuration
end # Beaneater