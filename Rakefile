require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  gem.name = "redis-mutex"
  gem.homepage = "http://github.com/kenn/redis-mutex"
  gem.license = "MIT"
  gem.summary = "Distrubuted non-blocking mutex in Ruby using Redis"
  gem.description = "Distrubuted non-blocking mutex in Ruby using Redis"
  gem.email = "kenn.ejima@gmail.com"
  gem.authors = ["Kenn Ejima"]
end
Jeweler::RubygemsDotOrgTasks.new

require 'rspec/core'
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = FileList['spec/**/*_spec.rb']
end

desc "Flush the test database"
task :flushdb do
  require 'redis-classy'
  Redis::Classy.db = Redis.new
  Redis::Classy.select 1
  Redis::Classy.flushdb
end

task :default => :spec

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "redis-mutex #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
