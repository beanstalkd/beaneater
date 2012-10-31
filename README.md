# Beaneater

[Beaneater](http://kr.github.com/beanstalkd/) is a simple, fast work queue. Its interface is generic, but was
originally designed for reducing the latency of page views in high-volume web
applications by running time-consuming tasks asynchronously. 
Read the [beanstalk protocol](https://github.com/kr/beanstalkd/blob/master/doc/protocol.md) for more detail.

## Installation

Install beaneater as a gem:

```
gem install beaneater
```

or add this to your Gemfile:

```ruby
# Gemfile
gem 'beaneater'
```

and run `bundle install` to install the dependency.

## Usage

### Connection

To interact with a beanstalk queue, first establish a connection by providing a set of addresses:

```ruby
@beanstalk = Beaneater::Pool.new(['10.0.1.5:11300'])
```

### Tubes

Beanstalkd has one or more tubes which can contain any number of jobs. 
Each tube consists of a _ready_, _delayed_, and _buried_ queue for jobs. 
To interact with a tube, first `find` the tube:

```ruby
@tube = @beanstalk.tubes.find "some-tube-here"
```

When a client connects, its watch list is initially just the tube named `default`.  
Tube names are at most 200 bytes. It specifies the tube to use. If the tube does not exist, it will be automatically created.

Tubes can have jobs inserted (put) into the used tube and jobs pulled out (reserved) from watched tubes. 
You can also see lists of tubes in various states:

```ruby
# The list-tubes command returns a list of all existing tubes
@beanstalk.tubes.all

# Returns the tube currently being used by the client (for insertion)
@beanstalk.tubes.used

# Returns a list tubes currently being watched by the client (for consumption)
@beanstalk.tubes.watched
```

To recap: each beanstalkd client manages two separate concerns: which tube newly created jobs are put into, 
and which tube(s) jobs are reserved from. Accordingly, there are two separate sets of functions for these concerns:

  * **use** and **using** affect where 'put' places jobs
  * **watch** and **watching** control where reserve takes jobs from

Note that these concerns are fully orthogonal: for example, when you 'use' a tube, it is not automatically 'watched'. 
Neither does 'watching' a tube affect the tube you are 'using'.

### Jobs

A job in beanstalk gets inserted by a client and includes the 'body' and job metadata.
Each job is enqueued into a tube and later reserved and processed. Here is a picture of the typical job lifecycle:

```
   put            reserve               delete
  -----> [READY] ---------> [RESERVED] --------> *poof*
```

A job at any given time is in one of three states: **ready**, **delayed**, or **buried**:

 * A **ready** job is waiting to be 'reserved' and processed after being 'put' onto a tube.
 * A **delayed** job is waiting to become ready after the specified delay.
 * A **buried** job has been reserved and buried, will not be reprocessed and is isolated for later use.

Similarly, there are several action that can be performed on a given job:
 
 * You can **reserve** which locks a job from the ready queue for processing.
 * You can **touch** which extends the time before a job is autoreleased back to ready.
 * You can **release** which places a reserved job back onto the ready queue.
 * You can **delete** which removes the job from the tube entirely. 
 * You can **bury** which places the job into the buried state.
 * You can **kick** which places a job from the buried queue back to ready.

You can put a job onto the beanstalk queue using the `put` command on a tube:

```ruby
@tube.put "job-data-here"
```

You can also specify additional metadata to control job behavior. In particular,
you can specify the `priority`, `delay`, and `ttr` of a particular job:

```ruby
# defaults are priority 0, delay of 0 and ttr of 120 seconds
@tube.put "job-data-here", :pri => 1000, :delay => 50, :ttr => 200
```

The `priority` argument is an integer < 2**32. Jobs with a smaller priority take precedence over jobs with larger priorities. 
The `delay` argument is an integer number of seconds to wait before putting the job in the ready queue.
The `ttr` argument is the time to run -- is an integer number of seconds to allow a worker to run this job. 

### Processing Jobs (Manual)

In order to process jobs, the worker should first specify the intended tubes to watch. If not specified, 
this will default to watching just the `default` tube.

```ruby
@beanstalk = Beaneater::Connection.new(['10.0.1.5:11300'])
@beanstalk.tubes.watch!('some-tube-name', 'some-other-tube')
```

Then you can use the `reserve` method which will return the
first available job within the watched tubes:

```ruby
job = @beanstalk.tubes.reserve
# => <Beaneater::Job id=5 body="foo">
puts job.body
# prints 'job-data-here'
print job.stats.state # => 'reserved'
```

By default, reserve will wait indefinitely for a job, if you want to specify a timeout,
simply pass the timeout (in seconds):


```ruby
job = @beanstalk.tubes.reserve(5) # wait 5 secs
# => <Beaneater::Job id=5 body="foo">
```

You can 'release' jobs back onto the ready queue to retry them later:

```ruby
job = @beanstalk.tubes.reserve
# ...job has ephemeral fail...
job.release :delay => 5
print job.stats.state # => 'delayed'
```

You can also 'delete' jobs that are finished:

```ruby
job = @beanstalk.tubes.reserve
# ...process job...
job.delete
```

Beanstalk jobs can also be buried if they fail, rather than being deleted:

```ruby
job = @beanstalk.tubes.reserve
# ...job fails...
job.bury
print job.stats.state # => 'buried'
```
Burying a job means that the job is pulled out of the queue into a special 'holding' area for later inspection or reuse.
To reanimate a buried job, you can mark buried jobs as ready with 'kick':

```ruby
@beanstalk.tubes.watch!('some-tube')
@beanstalk.tubes.kick(3)
```

This would kick 3 buried jobs for 'some-tube' back to the 'ready' state. Jobs can also be
inspected using the 'peek' commands. To find and peek at a particular job:

```ruby
@beanstalk.jobs.find(123)
# => <Beaneater::Job id=123 body="foo">
```

or you can peek at jobs on a tube:

```ruby
@tube = @beanstalk.tubes.find('foo')
@tube.peek(:ready)
# => <Beaneater::Job id=123 body="ready">
@tube.peek(:buried)
# => <Beaneater::Job id=456 body="buried">
@tube.peek(:delayed)
# => <Beaneater::Job id=789 body="delayed">
```

### Processing Jobs (Automatic)

Instead of using `watch` and `reserve`, you can also use the higher level `register` and `process` methods to
process jobs. First you can 'register' how to handle jobs from various tubes:

```ruby
@beanstalk.jobs.register('some-tube-name', :retry_on => [Timeout::Error]) do |job|
  do_something(job)
end

@beanstalk.jobs.register('some-other-name', :retry_on => [SomeCustomException]) do |job|
  do_something_else(job)
end
```

Once you have registered the handlers for known tubes, calling `process!` will begin an 'infinite' 
loop processing jobs as defined by the register blocks:

```ruby
@beanstalk.jobs.process!
```

Process runs the following pseudo-code steps:
 
 1. watch all registered tubes
 1. reserve the next job
 1. once job is reserved, invoke the registered handler based on the tube name
 1. if no exceptions occur, delete the job (success!)
 1. if 'retry_on' exceptions occur, call 'release' (retry!)
 1. if other exception occurs, call 'bury' (error!)
 1. repeat steps 2-5

This is well-suited for a 'worker' job processing process.

### Stats

Beanstalk has plenty of commands for introspecting the state of the queues and jobs. To get stats for
beanstalk overall:

```ruby
# Get overall stats about the job processing that has occurred
@beanstalk.stats
# => { 'current_connections': 1, 'current_jobs_buried': 0, 'current_jobs_delayed': 0, ... }
@beanstalk.stats.current_connections
# => 1
```

For stats on a particular tube:

```ruby
# Get statistical information about the specified tube if it exists
@beanstalk.tubes.find('some_tube_name').stats
# => { 'current_jobs_ready': 0, 'current_jobs_reserved': 0, 'current_jobs_buried': 0, ...  }
```

For stats on an individual job:

```ruby
# Get statistical information about the specified job if it exists
@beanstalk.job.find(some_job_id).stats
# => {'age': 0, 'id': 2, 'state': 'reserved', 'tube': 'default', ... }
```

Be sure to check the [beanstalk protocol](https://github.com/kr/beanstalkd/blob/master/doc/protocol.md) for
more details about the stats commands.

## Resources

There are other resources helpful when learning about beanstalk:

 * [Beanstalkd homepage](http://kr.github.com/beanstalkd/)
 * [beanstalk on github](https://github.com/kr/beanstalkd)
 * [beanstalk protocol](https://github.com/kr/beanstalkd/blob/master/doc/protocol.md)

## Contributors

 - [Nico Taing](https://github.com/Nico-Taing) - Creator and co-maintainer
 - [Nathan Esquenazi](https://github.com/nesquena) - Contributor and co-maintainer