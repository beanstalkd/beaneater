# frozen_string_literal: true

require "bundler/gem_tasks"
require 'rake/testtask'
require 'yard'
require 'redcarpet'
require 'json'
require 'net/http'
require_relative 'lib/beaneater/version'

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

# rake release:check (rake release runs it first, before it builds, tags or pushes):
# HEAD must be on master (or X.Y-stable), committed and not behind origin, version.rb
# must match the top CHANGELOG.md heading, stamped with a date, and neither the tag nor
# the gem version may exist yet.
desc "Check that HEAD can be released as beaneater #{Beaneater::VERSION}"
task "release:check" do
  version = Beaneater::VERSION
  tag = "v#{version}"
  git = ->(*args) { IO.popen(["git", *args], err: File::NULL, &:read).strip }
  errors = []

  errors << "git fetch origin failed" unless system("git", "fetch", "--quiet", "origin")
  branch = git.("rev-parse", "--abbrev-ref", "HEAD")
  stable = "#{version[/\A\d+\.\d+/]}-stable"
  errors << "on #{branch}, not master or #{stable}" unless ["master", stable].include?(branch)
  errors << "there are uncommitted changes" unless git.("status", "--porcelain").empty?
  unless system("git", "merge-base", "--is-ancestor", "origin/#{branch}", "HEAD", err: File::NULL)
    errors << "#{branch} is behind or diverged from origin/#{branch}"
  end

  heading = File.foreach(File.expand_path('CHANGELOG.md', __dir__)).find { |l| l.start_with?("## ") }.to_s.strip
  top, rest = heading.match(/\A## (\d+\.\d+\.\d+)( .*|)\z/)&.captures
  if top != version
    errors << "CHANGELOG.md starts with '#{heading}', not #{version}"
  elsif rest !~ /\b(19|20)\d\d\b/ || rest =~ /\b(unreleased|tbd|tba)\b/i
    errors << "CHANGELOG.md's '#{heading}' isn't stamped with a date"
  end

  unless git.("tag", "--list", tag).empty? && git.("ls-remote", "--tags", "origin", "refs/tags/#{tag}").empty?
    errors << "tag #{tag} already exists"
  end

  begin
    published = JSON.parse(Net::HTTP.get(URI("https://rubygems.org/api/v1/versions/beaneater.json")))
    errors << "beaneater #{version} is already on rubygems.org" if published.any? { |v| v["number"] == version }
  rescue StandardError => e
    errors << "couldn't check rubygems.org (#{e.message})"
  end

  abort "Not ready to release #{version}:\n#{errors.map { |e| "  - #{e}" }.join("\n")}" unless errors.empty?
  puts "Ready to release beaneater #{version} (#{git.("rev-parse", "--short", "HEAD")} on #{branch})"
end
Rake::Task["release"].prerequisites.unshift("release:check")

task :default => 'test:full'
