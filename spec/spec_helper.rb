require 'rubygems'
require 'bundler/setup'

require 'rspec'
require 'redis-mutex'

RSpec.configure do |config|
  # Use database 15 for testing so we don't accidentally step on you real data.
  RedisClassy.redis = Redis.new(db: 15)
  unless RedisClassy.keys.empty?
    abort '[ERROR]: Redis database 15 not empty! If you are sure, run "rake flushdb" beforehand.'
  end
end
