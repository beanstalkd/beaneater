class Beaneater
  class Configuration
    attr_accessor :default_put_delay   # default delay value to put a job
    attr_accessor :default_put_pri     # default priority value to put a job
    attr_accessor :default_put_ttr     # default ttr value to put a job
    attr_accessor :job_parser          # default job_parser to parse job body
    attr_accessor :job_serializer      # default serializer for job body
    attr_accessor :beanstalkd_url      # default beanstalkd url

    def initialize
      @default_put_delay   = 0
      @default_put_pri     = 65536
      @default_put_ttr     = 120
      @job_parser          = lambda { |body| body }
      @job_serializer      = lambda { |body| body }
      @beanstalkd_url      = nil
    end
  end # Configuration
end # Beaneater