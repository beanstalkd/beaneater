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
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  gem.add_development_dependency 'minitest', "~> 4.1.0"
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'mocha'
  gem.add_development_dependency 'fakeweb'
  gem.add_development_dependency 'term-ansicolor'
  gem.add_development_dependency 'json'
end
