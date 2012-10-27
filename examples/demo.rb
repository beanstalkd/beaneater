$:.unshift("../lib")
require 'beaneater'

# Establish a pool of beanstalks
bc = Beaneater::Pool.new(['localhost', 'localhost:11301', 'localhost:11302'])

# Print out key stats
p bc.stats.keys
p bc.stats.total_connections
p bc.stats[:total_connections]
p bc.stats['total_connections']

# find tube
tube = bc.tubes.find('tube2')
puts tube

# Put job onto tube
response = tube.put "foo bar", :priority => 1000, :ttr => 10, :delay => 0
p tube.peek :ready
p bc.tubes.watched


# Reserve job from tube

# Register and process jobs

# Get job from id

# bury job

# kick job

# Check job stats

# peek job

# peek tube

# list tubes

# pause tube