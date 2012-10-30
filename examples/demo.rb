require 'term/ansicolor'
class String; include Term::ANSIColor; end
def step(msg); "\n[STEP] #{msg}...".yellow; end
$:.unshift("../lib")
require 'beaneater'

# Establish a pool of beanstalks
puts step("Connecting to Beanstalk")
bc = Beaneater::Pool.new('localhost')
# bc = Beaneater::Pool.new(['localhost', 'localhost:11301', 'localhost:11302'])
puts bc

# Print out key stats
puts step("Print Stats")
p bc.stats.keys
p [bc.stats.total_connections, bc.stats[:total_connections], bc.stats['total_connections']]

# find tube
puts step("Find tube")
tube = bc.tubes.find('tube2')
puts tube

# Put job onto tube
puts step("Put job")
response = tube.put "foo bar", :pri => 1000, :ttr => 10, :delay => 0
puts response

# peek tube
puts step("Peek tube")
p tube.peek :ready

# watch tube
bc.tubes.watch!('tube2')

# Check tube stats
puts step("Get tube stats")
p tube.stats.keys
p tube.stats.name
p tube.stats.current_jobs_ready

# Reserve job from tube
puts step("Reserve job")
p job = bc.tubes.reserve
jid = job.id

# pause tube
puts step("Pause tube")
p tube.pause(1)

# Register jobs
puts step("Register jobs for tubes")
bc.jobs.register('tube_test', :retry_on => [Timeout::Error]) do |job|
 p 'tube_test'
 p job
 raise Beaneater::Jobs::AbortProcessException
end

bc.jobs.register('tube_test2', :retry_on => [Timeout::Error]) do |job|
 p 'tube_test2'
 p job
 raise Beaneater::Jobs::AbortProcessException
end

p bc.jobs.processors

response = bc.tubes.find('tube_test').put "foo register", :pri => 1000, :ttr => 10, :delay => 0
response = bc.tubes.find('tube_test2').put "foo baz", :pri => 1000, :ttr => 10, :delay => 0

# Process jobs
puts step("Process jobs")
2.times { bc.jobs.process! }

# Get job from id (peek job)
puts step("Get job from id")
p bc.jobs.find(jid)
p bc.jobs.peek(jid)

# Check job stats
puts step("Get job stats")
p job.stats.keys
p job.stats.tube
p job.stats.state

# bury job
puts step("Bury job")
p job.bury

# delete job
puts step("Delete job")
p job.delete

# list tubes
puts step("List tubes")
p bc.tubes.watched
p bc.tubes.used
p bc.tubes.all