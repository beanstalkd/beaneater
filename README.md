# Beanstalk Ruby Client

Beanstalk is a simple, fast work queue. Its interface is generic, but was
originally designed for reducing the latency of page views in high-volume web
applications by running time-consuming tasks asynchronously.

## Installation

Install beanstalk-client as a gem:

```
gem install beanstalk-client
```

or add to your Gemfile:

```ruby
# Gemfile
gem 'beanstalk-client'
```

and run `bundle install` to install the dependency.

## Usage

### Connection

To interact with a beanstalk queue, first establish a client connection by providing host and port:

```ruby
@beanstalk = Beanstalk::Pool.new(['10.0.1.5:11300'])
```

### Tubes

The system has one or more tubes which contain jobs. Each tube consists of a ready queue and a delay queue for jobs. 
When a client connects, its watch list is initially just the tube named `default`. 
If it submits jobs without having sent a `use` command, they will live in the tube named `default`.
You can specify the tube for a connection with:

```ruby
@beanstalk.use "some-tube-here" # 'default' if unspecified
```

Tube names are at most 200 bytes. It specifies the tube to use. 
If the tube does not exist, it will be created.

### Jobs

A job in beanstalk gets created by a client and includes a 'body' which con contain all relevant job metadata.
With BeanEater, a job is enqueued onto beanstalk and then later reserved and processed. 
Here is a picture of the typical job lifecycle:

```
   put            reserve               delete
  -----> [READY] ---------> [RESERVED] --------> *poof*
```

You can `put` a job onto the beanstalk queue using the `put` command:

```ruby
@beanstalk.put "job-data-here"
```

You can also specify additional metadata to control job processing parameters. Specifically,
you can set the `priority`, `delay`, and `ttr` of a particular job:

```ruby
# defaults are priority 0, delay of 0 and ttr of 120 seconds
@beanstalk.put "job-data-here", 1000, 50, 200
```

The `priority` argument is an integer < 2**32. Jobs with a smaller priority take precedence over jobs with larger priorities. 
The `delay` argument is an integer number of seconds to wait before putting the job in the ready queue.
The `ttr` argument is the time to run -- is an integer number of seconds to allow a worker to run this job. 

### Processing Jobs

In order to process jobs, the worker first needs to specify which tubes to `watch` for new jobs:

```ruby
@beanstalk = Beanstalk::Pool.new(['10.0.1.5:11300'])
@beanstalk.watch('some-tube-name')
@beanstalk.watch('some-other-tune')
```

and perhaps even which tubes to `ignore` (including 'default'):

```ruby
@beanstalk.ignore('default')
```

and then we can begin to `reserve` jobs. This will find the first job available and 
return the job for processing: 

```ruby
job = @beanstalk.reserve
# => <Beanstalk::Job>
puts job.body
# prints 'job-data-here'
```

You can process each new job as they become available using a loop:

```ruby
loop do
  job = beanstalk.reserve # waits for a job
  puts job.body # prints "hello"
  job.delete # remove job after processing
end
```

Beanstalk jobs can also be buried if they fail, rather than deleted:

```ruby
job = @beanstalk.reserve
# ...job fails...
job.bury
```
Burying a job means that the job is pulled out of the 
queue into a special 'holding' area for later inspection or reuse.

### Stats

Beanstalk has plenty of commands for introspecting the state of the queues and jobs. These methods include:

```ruby
# Get overall stats about the state of beanstalk and processing that has occured
@beanstalk.stats

# Get statistical information about the specified job if it exists
@beanstalk.job_stats(some_job_id)

# Get statistical information about the specified tube if it exists
@beanstalk.stats_tube(some_tube_name)

# The list-tubes command returns a list of all existing tubes
@beanstalk.list_tubes

# Returns the tube currently being used by the client
@beanstalk.list_tube_used

# Returns a list tubes currently being watched by the client
@beanstalk.list_tubes_watched
```

Be sure to check the [beanstalk protocol](http://github.com/kr/beanstalkd/raw/master/doc/protocol.txt) file for
a more detailed looks at stats commands.

## Resources

There are other resources helpful when learning about beanstalk:

 * [Beanstalkd homepage](http://kr.github.com/beanstalkd/)
 * [beanstalk-ruby-client](https://github.com/kr/beanstalk-client-ruby)
 * [beanstalk protocol](http://github.com/kr/beanstalkd/raw/master/doc/protocol.txt)

## Contributors

 - Isaac Feliu
 - Peter Kieltyka
 - Martyn Loughran
 - Dustin Sallings