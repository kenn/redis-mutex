$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'rspec'
require 'redis-mutex'

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

Redis::Classy.db = Redis.new
Redis::Classy.select 1
unless Redis::Classy.keys.empty?
  puts '[ERROR]: Redis database 1 not empty! run "rake flushdb" beforehand.'
  exit!
end

RSpec.configure do |config|
end
