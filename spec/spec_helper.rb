$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'rspec'
require 'redis-mutex'

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
  # Use database 15 for testing so we don't accidentally step on you real data.
  Redis::Classy.db = Redis.new(:db => 15)
  unless Redis::Classy.keys.empty?
    puts '[ERROR]: Redis database 15 not empty! run "rake flushdb" beforehand.'
    exit!
  end
end
