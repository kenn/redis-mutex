require 'rubygems'
require 'bundler/setup'

require 'rspec'
require 'redis-mutex'

RSpec.configure do |config|
  if ENV['CI'] == 'true'
    RedisClassy.redis = Redis.new
  else
    # Use database 15 for testing so we don't accidentally step on you real data.
    RedisClassy.redis = Redis.new(db: 15)
  end
  unless RedisClassy.keys.empty?
    abort '[ERROR]: Redis database is not empty! If you are sure, run "rake flushdb" beforehand.'
  end
end
