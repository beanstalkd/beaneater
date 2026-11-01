# frozen_string_literal: true
# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'beaneater/version'

Gem::Specification.new do |gem|
  gem.name          = "beaneater"
  gem.version       = Beaneater::VERSION
  gem.authors       = ["Nico Taing"]
  gem.email         = ["nico.taing@gmail.com"]
  gem.description   = %q{Simple beanstalkd client for ruby}
  gem.summary       = %q{Simple beanstalkd client for ruby.}
  gem.homepage      = "https://github.com/beanstalkd/beaneater"
  gem.license       = 'MIT'
  gem.metadata      = {
    "changelog_uri"         => "https://github.com/beanstalkd/beaneater/blob/master/CHANGELOG.md",
    "source_code_uri"       => "https://github.com/beanstalkd/beaneater",
    "bug_tracker_uri"       => "https://github.com/beanstalkd/beaneater/issues",
    "rubygems_mfa_required" => "true"
  }

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  gem.required_ruby_version = '>= 2.7'
  gem.add_development_dependency 'minitest', "~> 4.1.0"
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'mocha'
  gem.add_development_dependency 'term-ansicolor'
  gem.add_development_dependency 'json'
end
