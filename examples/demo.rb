require 'term/ansicolor'

class String
  include Term::ANSIColor
end
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
p bc.stats.total_connections
p bc.stats[:total_connections]
p bc.stats['total_connections']

# find tube
puts step("Find tube")
tube = bc.tubes.find('tube2')
puts tube

# Put job onto tube
puts step("Put job")
response = tube.put "foo bar", :priority => 1000, :ttr => 10, :delay => 0
puts response

# peek tube
puts step("Peek tube")
p tube.peek :ready

# watch tube
bc.tubes.watch!('tube2')

# Reserve job from tube
puts step("Reserve job")
p tube.reserve
p bc.tubes.reserve

# Register and process jobs
puts step("Process jobs")

# Get job from id
puts step("Get job from id")

# Check job stats
puts step("Get job stats")

# peek job
puts step("Peek job")

# delete job
puts step("Delete job")

# bury job
puts step("Bury job")

# kick job
puts step("Kick job")

# list tubes
puts step("List tubes")
p bc.tubes.watched

# pause tube
puts step("Pause tube")

# resume tube
puts step("Resume tube")