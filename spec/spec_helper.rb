require 'rubygems'
require 'bundler/setup'

require 'rspec'
require 'redis-mutex'

RSpec.configure do |config|
  config.add_setting :redis_connection

  redis = Redis.new(:db => 15)
  Redis::Mutex.default_redis = redis

  unless redis.keys.empty?
    puts '[ERROR]: Redis database 15 not empty! If you are sure, run "rake flushdb" beforehand.'
    exit!
  end

  config.before(:suite) { RSpec.configuration.redis_connection = redis }
end
