$:.unshift("../lib")
require 'beaneater'

# Establish a pool of beanstalks
bc = Beaneater::Connection.new(['localhost'])

# Print out key stats
p bc.stats.keys
p bc.stats.total_connections
p bc.stats[:total_connections]
p bc.stats['total_connections']

# find tube
tube = bc.tubes.find('tube2')
puts tube

# Put job onto tube

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