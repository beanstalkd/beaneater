module Beaneater
  class Configuration
    attr_accessor :default_put_delay   # default delay value to put a job
    attr_accessor :default_put_pri     # default priority value to put a job
    attr_accessor :default_put_ttr     # default ttr value to put a job
    attr_accessor :job_parser          # default job_parser to parse job body
    attr_accessor :beanstalkd_url      # default beanstalkd url
    attr_accessor :socket_class        # default TCPSocket

    def initialize
      @default_put_delay   = 0
      @default_put_pri     = 65536
      @default_put_ttr     = 120
      @job_parser          = lambda { |body| body }
      @beanstalkd_url      = nil
      @socket_class        = TCPSocket
    end
  end # Configuration
end # Beaneater