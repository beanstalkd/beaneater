# Beaneater

Beaneater is the best way to interact with beanstalkd from within Ruby. 
[Beanstalkd](http://kr.github.com/beanstalkd/) is a simple, fast work queue. Its interface is generic, but was
originally designed for reducing the latency of page views in high-volume web applications by 
running time-consuming tasks asynchronously. Read the 
[beanstalk protocol](https://github.com/kr/beanstalkd/blob/master/doc/protocol.md) for more details. 


## Why Beanstalk?

Illya has an excellent blog post
[Scalable Work Queues with Beanstalk](http://www.igvita.com/2010/05/20/scalable-work-queues-with-beanstalk/) and
Adam Wiggins posted [an excellent comparison](http://adam.heroku.com/past/2010/4/24/beanstalk_a_simple_and_fast_queueing_backend/).

You will quickly see that **beanstalkd** is an underrated but incredible project that is extremely well-suited as a job queue.
Significantly better suited for this task than Redis or a database. Beanstalk is a simple,
and a very fast work queue service rolled into a single binary - it is the memcached of work queues.
Originally built to power the backend for the 'Causes' Facebook app, it is a mature and production ready open source project.
[PostRank](http://www.postrank.com) uses beanstalk to reliably process millions of jobs a day.

A single instance of Beanstalk is perfectly capable of handling thousands of jobs a second (or more, depending on your job size)
because it is an in-memory, event-driven system. Powered by libevent under the hood,
it requires zero setup (launch and forget, à la memcached), optional log based persistence, an easily parsed ASCII protocol,
and a rich set of tools for job management that go well beyond a simple FIFO work queue.

Beanstalkd supports the following features out of the box:

| Feature | Description                     |
| ------- | ------------------------------- |
| **Parallel Queues** | Supports multiple work queues created on demand. |
| **Reliable**        | Beanstalk’s reserve, work, delete cycle ensures reliable processing. |
| **Scheduling**      | Delay enqueuing jobs by a specified interval to schedule processing later |
| **Fast**            | Processes thousands of jobs per second; **significantly** faster than alternatives. |
| **Priorities**      | Specify priority so important jobs can be processed quickly. |
| **Persistence**     | Jobs are stored in memory for speed, but logged to disk for safe keeping. |
| **Federation**      | Horizontal scalability provided through federation by the client. |
| **Buried jobs**     | Bury any job which causes an error for later debugging and inspection.|

Keep in mind that these features are supported out of the box with beanstalk and require no special code within this gem to support.
In the end, **beanstalk is the ideal job queue** while also being ridiculously easy to install and setup.

## Installation

Install beanstalkd:

Mac OS

```
brew update
brew install beanstalkd
beanstalkd -p 11300
```

Ubuntu

```
apt-get install beanstalkd
beanstalkd -p 11300
```

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

You can conversely close and dispose of a pool at any time with:

```ruby
@beanstalk.close
```

### Tubes

Beanstalkd has one or more tubes which can contain any number of jobs. 
Jobs can be inserted (put) into the used tube and pulled out (reserved) from watched tubes. 
Each tube consists of a _ready_, _delayed_, and _buried_ queue for jobs. 

When a client connects, its watch list is initially just the tube named `default`.  
Tube names are at most 200 bytes. It specifies the tube to use. If the tube does not exist, it will be automatically created.

To interact with a tube, first `find` the tube:

```ruby
@tube = @beanstalk.tubes.find "some-tube-here"
# => <Tube name='some-tube-here'>
```

To reserve jobs from beanstalk, you will need to 'watch' certain tubes:

```ruby
# Watch only the tubes listed below (!)
@beanstalk.tubes.watch!('some-tube')
# Append tubes to existing set of watched tubes
@beanstalk.tubes.watch('another-tube')
# You can also ignore tubes that have been watched previously
@beanstalk.tubes.ignore('some-tube')
```

You can easily get a list of all, used or watched tubes:

```ruby
# The list-tubes command returns a list of all existing tubes
@beanstalk.tubes.all
# => [<Tube name='foo'>, <Tube name='bar'>]

# Returns the tube currently being used by the client (for insertion)
@beanstalk.tubes.used
# => <Tube name='bar'>

# Returns a list tubes currently being watched by the client (for consumption)
@beanstalk.tubes.watched
# => [<Tube name='foo'>]
```

You can also temporarily 'pause' the execution of a tube by specifying the time:

```ruby
tube = @beanstalk.tubes["some-tube-here"]
tube.pause(3) # pauses tube for 3 seconds
```

or even clear the tube of all jobs:

```ruby
tube = @beanstalk.tubes["some-tube-here"]
tube.clear # tube will now be empty
```

In summary, each beanstalk client manages two separate concerns: which tube newly created jobs are put into, 
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

| State   | Description                     |
| ------- | ------------------------------- |
| ready   | waiting to be `reserved` and processed after being `put` onto a tube. |
| delayed | waiting to become `ready` after the specified delay. |
| buried  | waiting to be kicked, usually after job fails to process |

In addition, there are several actions that can be performed on a given job, you can:
 
 * **reserve** which locks a job from the ready queue for processing.
 * **touch** which extends the time before a job is autoreleased back to ready.
 * **release** which places a reserved job back onto the ready queue.
 * **delete** which removes a job from beanstalk. 
 * **bury** which places a reserved job into the buried state.
 * **kick** which places a buried job from the buried queue back to ready.

You can insert a job onto a beanstalk tube using the `put` command:

```ruby
@tube.put "job-data-here"
```

Each job has various metadata associated such as `priority`, `delay`, and `ttr` which can be 
specified as part of the `put` command:

```ruby
# defaults are priority 0, delay of 0 and ttr of 120 seconds
@tube.put "job-data-here", :pri => 1000, :delay => 50, :ttr => 200
```

The `priority` argument is an integer < 2**32. Jobs with a smaller priority take precedence over jobs with larger priorities. 
The `delay` argument is an integer number of seconds to wait before putting the job in the ready queue.
The `ttr` argument is the time to run -- is an integer number of seconds to allow a worker to run this job. 

### Processing Jobs (Manually)

In order to process jobs, the client should first specify the intended tubes to be watched. If not specified, 
this will default to watching just the `default` tube. 

```ruby
@beanstalk = Beaneater::Connection.new(['10.0.1.5:11300'])
@beanstalk.tubes.watch!('tube-name', 'other-tube')
```

Next you can use the `reserve` command which will return the first available job within the watched tubes:

```ruby
job = @beanstalk.tubes.reserve
# => <Beaneater::Job id=5 body="foo">
puts job.body
# prints 'job-data-here'
print job.stats.state # => 'reserved'
```

By default, reserve will wait indefinitely for the next job. If you want to specify a timeout,
simply pass that in seconds into the command:

```ruby
job = @beanstalk.tubes.reserve(5) # wait 5 secs for a job, then return
# => <Beaneater::Job id=5 body="foo">
```

You can 'release' a reserved job back onto the ready queue to retry later:

```ruby
job = @beanstalk.tubes.reserve
# ...job has ephemeral fail...
job.release :delay => 5
print job.stats.state # => 'delayed'
```

You can also 'delete' jobs that are finished:

```ruby
job = @beanstalk.tubes.reserve
job.touch # extends ttr for job
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
To reanimate this job later, you can 'kick' buried jobs back into being ready:

```ruby
@beanstalk.tubes['some-tube'].kick(3)
```

This kicks 3 buried jobs for 'some-tube' back into the 'ready' state. Jobs can also be
inspected using the 'peek' commands. To find and peek at a particular job based on the id:

```ruby
@beanstalk.jobs.find(123)
# => <Beaneater::Job id=123 body="foo">
```

or you can peek at jobs within a tube:

```ruby
@tube = @beanstalk.tubes.find('foo')
@tube.peek(:ready)
# => <Beaneater::Job id=123 body="ready">
@tube.peek(:buried)
# => <Beaneater::Job id=456 body="buried">
@tube.peek(:delayed)
# => <Beaneater::Job id=789 body="delayed">
```

When dealing with jobs there are a few other useful commands available:

```ruby
job = @beanstalk.tubes.reserve
print job.tube      # => "some-tube-name"
print job.reserved? # => true
print job.exists?   # => true
job.delete
print job.exists?   # => false
```

### Processing Jobs (Automatically)

Instead of using `watch` and `reserve`, you can also use the higher level `register` and `process` methods to
process jobs. First you can 'register' how to handle jobs from various tubes:

```ruby
@beanstalk.jobs.register('some-tube', :retry_on => [SomeError]) do |job|
  do_something(job)
end

@beanstalk.jobs.register('other-tube') do |job|
  do_something_else(job)
end
```

Once you have registered the handlers for known tubes, calling `process!` will begin a
loop processing jobs as defined by the registered processor blocks:

```ruby
@beanstalk.jobs.process!
```

Processing runs the following steps:
 
 1. Watch all registered tubes
 1. Reserve the next job
 1. Once job is reserved, invoke the registered handler based on the tube name
 1. If no exceptions occur, delete the job (success)
 1. If 'retry_on' exceptions occur, call 'release' (retry)
 1. If other exception occurs, call 'bury' (error)
 1. Repeat steps 2-5

The `process` command is ideally suited for a beanstalk job processing daemon.

### Handling Errors

While using Beaneater, certain errors may be encountered. Errors are encountered when
a command is sent to beanstalk and something unexpected happens. The most common errors
are listed below:

| Errors                      | Description   |
| --------------------        | ------------- |
| Beaneater::NotConnected     | Client connection to beanstalk cannot be established. |
| Beaneater::InvalidTubeName  | Specified tube name for use or watch is not valid.    |
| Beaneater::NotFoundError    | Specified job or tube could not be found.             |
| Beaneater::TimedOutError    | Job could not be reserved within time specified.      |

There are other exceptions that are less common such as `OutOfMemoryError`, `DrainingError`,
`DeadlineSoonError`, `InternalError`, `BadFormatError`, `UnknownCommandError`,
`ExpectedCRLFError`, `JobTooBigError`, `NotIgnoredError`. Be sure to check the 
[beanstalk protocol](https://github.com/kr/beanstalkd/blob/master/doc/protocol.md) for more information.


### Stats

Beanstalk has plenty of commands for introspecting the state of the queues and jobs. To get stats for
beanstalk overall:

```ruby
# Get overall stats about the job processing that has occurred
print @beanstalk.stats
# => { 'current_connections': 1, 'current_jobs_buried': 0, ...
print @beanstalk.stats.current_connections
# => 1
```

For stats on a particular tube:

```ruby
# Get statistical information about the specified tube if it exists
print @beanstalk.tubes['some_tube_name'].stats
# => { 'current_jobs_ready': 0, 'current_jobs_reserved': 0, ...
```

For stats on an individual job:

```ruby
# Get statistical information about the specified job if it exists
print @beanstalk.jobs[some_job_id].stats
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