# -*- encoding: utf-8 -*-

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
  gem.version       = '3.0.0' # retrieve this value by: Gem.loaded_specs['redis-mutex'].version.to_s

  gem.add_runtime_dependency "redis-namespace", "~> 1.0"
  gem.add_development_dependency "rspec"
  gem.add_development_dependency "bundler"

  # For Travis
  gem.add_development_dependency "rake"
end
