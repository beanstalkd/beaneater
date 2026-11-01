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
# HEAD must be on master (or X.Y-stable), committed and at the remote branch it will be
# pushed to (`origin` unless `rake release[remote]` or the branch's upstream says
# otherwise), version.rb must match the top CHANGELOG.md heading, stamped with a date,
# and neither the tag nor the gem version may exist yet.
desc "Check that HEAD can be released as beaneater #{Beaneater::VERSION}"
task "release:check", [:remote] do |_, args|
  version = Beaneater::VERSION
  tag = "v#{version}"
  git = ->(*a) { out = IO.popen(["git", *a], err: File::NULL, &:read); out.strip if $?.success? }
  errors = []

  branch = git.("rev-parse", "--abbrev-ref", "HEAD").to_s
  remote = args[:remote] || git.("config", "--get", "branch.#{branch}.remote") || "origin"
  errors << "git fetch #{remote} failed" unless system("git", "fetch", "--quiet", remote)
  stable = "#{version[/\A\d+\.\d+/]}-stable"
  errors << "on #{branch}, not master or #{stable}" unless ["master", stable].include?(branch)
  errors << "there are uncommitted changes" unless git.("status", "--porcelain") == ""
  head = git.("rev-parse", "HEAD")
  unless head && head == git.("rev-parse", "--verify", "--quiet", "refs/remotes/#{remote}/#{branch}")
    errors << "#{branch} is not at #{remote}/#{branch} (push or pull first; release a merged commit)"
  end

  heading = File.foreach(File.expand_path('CHANGELOG.md', __dir__), encoding: "bom|utf-8").find { |l| l.start_with?("## ") }.to_s.strip
  top, rest = heading.match(/\A## (\d+\.\d+\.\d+)( .*|)\z/)&.captures
  if top != version
    errors << "CHANGELOG.md starts with '#{heading}', not #{version}"
  elsif rest !~ /\b(19|20)\d\d\b/ || rest =~ /\b(unreleased|tbd|tba)\b/i
    errors << "CHANGELOG.md's '#{heading}' isn't stamped with a date"
  end

  local_tag = git.("tag", "--list", tag)
  remote_tag = git.("ls-remote", "--tags", remote, "refs/tags/#{tag}")
  if local_tag.nil? || remote_tag.nil?
    errors << "couldn't check for tag #{tag}"
  elsif !(local_tag.empty? && remote_tag.empty?)
    page = args[:remote] ? "rake 'release:github[#{args[:remote]}]'" : "rake release:github"
    errors << "tag #{tag} already exists (if only the gem push failed: gem push pkg/beaneater-#{version}.gem, then #{page})"
  end

  begin
    published = JSON.parse(Net::HTTP.get(URI("https://rubygems.org/api/v1/versions/beaneater.json")))
    errors << "beaneater #{version} is already on rubygems.org" if published.any? { |v| v["number"] == version }
  rescue StandardError => e
    errors << "couldn't check rubygems.org (#{e.message})"
  end

  abort "Not ready to release #{version}:\n#{errors.map { |e| "  - #{e}" }.join("\n")}" unless errors.empty?
  puts "Ready to release beaneater #{version} (#{git.("rev-parse", "--short", "HEAD")} on #{branch}, #{remote})"
end
Rake::Task["release"].prerequisites.unshift("release:check")
%w[release:source_control_push release:rubygem_push].each { |t| Rake::Task[t].enhance(["release:check"]) }

# rake release:github (rake release runs it last, once the tag and the gem are pushed):
# creates the GitHub release page for the tag through the gh CLI, on the github.com
# repository the remote pushes to, with a link to the CHANGELOG and GitHub's generated
# notes since the previous version's tag. It is marked Latest only when no higher version
# is tagged, so a release from an X.Y-stable branch doesn't take that from a newer one.
# If the page already exists it does nothing, so it can also be run by hand to finish a release.
desc "Create the GitHub release page for v#{Beaneater::VERSION}"
task "release:github", [:remote] do |_, args|
  version = Gem::Version.new(Beaneater::VERSION)
  tag = "v#{version}"
  git = ->(*a) { out = IO.popen(["git", *a], err: File::NULL, &:read); out.strip if $?.success? }
  branch = git.("rev-parse", "--abbrev-ref", "HEAD").to_s
  remote = args[:remote] || git.("config", "--get", "branch.#{branch}.remote") || "origin"
  url = git.("remote", "get-url", "--push", remote).to_s.split("\n").first.to_s
  repo = url[%r{(?:\A|[@/.])github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?\z}i, 1] or abort "#{remote} isn't a GitHub repository"
  # the push URL's tags, not the fetch URL's: the page goes to the repository the tag was pushed to
  tags = git.("ls-remote", "--tags", url, "refs/tags/v*") or abort "Couldn't list the tags on #{remote}"
  tagged = tags.split("\n").filter_map { |l| l[%r{\trefs/tags/v(\d+\.\d+\.\d+)\z}, 1] }.map { |v| Gem::Version.new(v) }
  previous = tagged.select { |v| v < version }.max
  options = ["--latest=#{tagged.none? { |v| v > version }}"]
  options += ["--notes-start-tag", "v#{previous}"] if previous
  # gh adds the generated notes after a single newline; the second one keeps them out of this paragraph
  notes = "See [CHANGELOG.md](https://github.com/#{repo}/blob/#{tag}/CHANGELOG.md) for what changed, and what to do when upgrading.\n"
  gh_repo = "github.com/#{repo}" # so an exported GH_HOST doesn't send it elsewhere

  if system("gh", "release", "view", tag, "-R", gh_repo, out: File::NULL, err: File::NULL)
    puts "GitHub release #{tag} already exists on #{repo}"
  elsif system("gh", "release", "create", tag, "-R", gh_repo, "--verify-tag", "--title", tag, *options,
               "--generate-notes", "--notes", notes)
    puts "Created GitHub release #{tag} on #{repo}"
  else
    abort "Couldn't create GitHub release #{tag} on #{repo} (is gh installed and signed in?)"
  end
end
# The gem is out by then, so a failure here only warns and says how to finish.
Rake::Task["release"].enhance do |_, args|
  if %w[n no nil false off 0].include?(ENV["gem_push"].to_s.downcase)
    puts "gem_push is off, so no GitHub release page"
    next
  end
  begin
    Rake::Task["release:github"].invoke(args[:remote])
  rescue SystemExit, StandardError => e
    warn "#{e.class}: #{e.message} (#{e.backtrace&.first})" unless e.is_a?(SystemExit)
    page = args[:remote] ? "rake 'release:github[#{args[:remote]}]'" : "rake release:github"
    warn "The tag and the gem are pushed; only the GitHub release page is missing. Run: #{page}"
  end
end

task :default => 'test:full'
