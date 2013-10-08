require "bundler/gem_tasks"
require 'rake/testtask'
require 'yard'
require 'redcarpet'

# rake test
Rake::TestTask.new do |t|
  t.libs.push "lib"
  t.test_files = FileList[File.expand_path('../test/**/*_test.rb', __FILE__)] -
    FileList[File.expand_path('../test/**/beaneater_test.rb', __FILE__)]
  t.verbose = true
end

# rake test:integration
Rake::TestTask.new("test:integration") do |t|
  t.libs.push "lib"
  t.test_files = FileList[File.expand_path('../test/**/beaneater_test.rb', __FILE__)]
  t.verbose = true
end

# rake test:full
Rake::TestTask.new("test:full") do |t|
  t.libs.push "lib"
  t.test_files = FileList[File.expand_path('../test/**/*_test.rb', __FILE__)]
  t.verbose = true
end

YARD::Rake::YardocTask.new do |t|
  t.files   = ['lib/beaneater/**/*.rb']
  t.options = []
end

task :default => 'test:full'
