#!/usr/bin/env rake
require "bundler/gem_tasks"

# RSpec
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new('spec')
task :default => :spec

# Custom Tasks
desc 'Flush the test database'
task :flushdb do
  require 'redis'
  if ENV['ci'] == 'true'
    Redis.new.flushdb
  else
    Redis.new(db: 15).flushdb
  end
end
