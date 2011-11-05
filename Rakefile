require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake/file_utils'
include FileUtils

require 'jeweler'
Jeweler::Tasks.new do |gem|
  gem.name = "redis-mutex"
  gem.homepage = "http://github.com/kenn/redis-mutex"
  gem.license = "MIT"
  gem.summary = "Distrubuted mutex using Redis"
  gem.description = "Distrubuted mutex using Redis"
  gem.email = "kenn.ejima@gmail.com"
  gem.authors = ["Kenn Ejima"]
end
Jeweler::RubygemsDotOrgTasks.new

desc "Flush the test database"
task :flushdb do
  require 'redis-classy'
  Redis::Classy.db = Redis.new(:db => 15)
  Redis::Classy.flushdb
end

task :default => :spec
task :spec do
  exec "rspec spec"
end
