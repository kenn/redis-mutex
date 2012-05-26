# -*- encoding: utf-8 -*-
# WARNING: do not directly load redis/mutex/version so avoid superclass mismatch. load from the top instead.
require File.expand_path('../lib/redis-mutex', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Kenn Ejima"]
  gem.email         = ["kenn.ejima@gmail.com"]
  gem.description   = %q{Distrubuted mutex using Redis}
  gem.summary       = %q{Distrubuted mutex using Redis}
  gem.homepage      = "http://github.com/kenn/redis-mutex"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "redis-mutex"
  gem.require_paths = ["lib"]
  gem.version       = Redis::Mutex::VERSION

  gem.add_runtime_dependency "redis-classy", "~> 1.0"
  gem.add_runtime_dependency "redis"
  gem.add_development_dependency "rspec"
  gem.add_development_dependency "bundler"

  # For Travis
  gem.add_development_dependency "rake"
end
