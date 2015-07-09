Redis Mutex
===========

[![Build Status](https://secure.travis-ci.org/kenn/redis-mutex.png)](http://travis-ci.org/kenn/redis-mutex)

Distributed mutex in Ruby using Redis. Supports both **blocking** and **non-blocking** semantics.

The idea was taken from [the official SETNX doc](http://redis.io/commands/setnx).

Synopsis
--------

In the following example, only one thread / process / server can enter the locked block at one time.

```ruby
RedisMutex.with_lock(:your_lock_name) do
  # do something exclusively
end
```

or

```ruby
mutex = RedisMutex.new(:your_lock_name)
if mutex.lock
  # do something exclusively
  mutex.unlock
else
  puts "failed to acquire lock!"
end
```

By default, while one is holding a lock, others wait **1 second** in total, polling **every 100ms** to see if the lock was released.
When 1 second has passed, the lock method returns `false` and others give up. Note that if your job runs longer than **10 seconds**,
the lock will be automatically removed to avoid a deadlock situation in case your job is dead before releasing the lock. Also note
that you can configure any of these timing values, as explained later.

Or if you want to immediately receive `false` on an unsuccessful locking attempt, you can change the mutex mode to **non-blocking**.

Changelog
---------

### v4.0

`redis-mutex` 4.0 has brought a few backward incompatible changes to follow the major upgrade of the underlying `redis-classy` gem.

* The base class `Redis::Mutex` is now `RedisMutex`.
* `Redis::Classy.db = Redis.new` is now `RedisClassy.redis = Redis.new`.

### v3.0

* Ruby 2.0 or later is required.
* `auto_mutex` now takes `:on` for additional key scoping.

### v2.0

* **Exception-based control flow**: Added `lock!` and `unlock!`, which raises an exception when fails to acquire a lock. Raises `RedisMutex::LockError` and `RedisMutex::UnlockError` respectively.
* **INCOMPATIBLE CHANGE**: `#lock` no longer accepts a block. Use `#with_lock` instead, which uses `lock!` internally and returns the value of block.
* `unlock` returns boolean values for success / failure, for consistency with `lock`.

Install
-------

    gem install redis-mutex

Usage
-----

In Gemfile:

```ruby
gem 'redis-mutex'
```

Register the Redis server: (e.g. in `config/initializers/redis_mutex.rb` for Rails)

```ruby
RedisClassy.redis = Redis.new
```

Note that Redis Mutex uses the `redis-classy` gem internally to organize keys in an isolated namespace.

There are a number of methods:

```ruby
mutex = RedisMutex.new(key, options)    # Configure a mutex lock
mutex.lock                                # Try to acquire the lock, returns false when failed
mutex.lock!                               # Try to acquire the lock, raises exception when failed
mutex.unlock                              # Try to release the lock, returns false when failed
mutex.unlock!                             # Try to release the lock, raises exception when failed
mutex.locked?                             # Find out if resource already locked
mutex.with_lock                           # Try to acquire the lock, execute the block, then return the value of the block.
                                          # Raises exception when failed to acquire the lock.

RedisMutex.sweep                        # Remove all expired locks
RedisMutex.with_lock(key, options)      # Shortcut to new + with_lock
```

The key argument can be symbol, string, or any Ruby objects that respond to `id` method, where the key is automatically set as
`TheClass:id`. For any given key, `RedisMutex:` prefix will be automatically prepended. For instance, if you pass a `Room`
object with id of `123`, the actual key in Redis will be `RedisMutex:Room:123`. The automatic prefixing and instance binding
is the feature of `RedisClassy` - for more internal details, refer to [Redis Classy](https://github.com/kenn/redis-classy).

The initialize method takes several options.

```ruby
:block  => 1    # Specify in seconds how long you want to wait for the lock to be released.
                # Specify 0 if you need non-blocking sematics and return false immediately. (default: 1)
:sleep  => 0.1  # Specify in seconds how long the polling interval should be when :block is given.
                # It is NOT recommended to go below 0.01. (default: 0.1)
:expire => 10   # Specify in seconds when the lock should be considered stale when something went wrong
                # with the one who held the lock and failed to unlock. (default: 10)
```

The lock method returns `true` when the lock has been successfully acquired, or returns `false` when the attempts failed after
the seconds specified with **:block**. When 0 is given to **:block**, it is set to **non-blocking** mode and immediately returns `false`.

In the following Rails example, only one request can enter to a given room.

```ruby
class RoomController < ApplicationController
  before_filter { @room = Room.find(params[:id]) }
  
  def enter
    RedisMutex.with_lock(@room) do    # key => "Room:123"
      # do something exclusively
    end
    render text: 'success!'
  rescue RedisMutex::LockError
    render text: 'failed to acquire lock!'
  end
end
```

Note that you need to explicitly call the `unlock` method when you don't use `with_lock` and its block syntax. Also it is recommended to
put the `unlock` method in the `ensure` clause.

```ruby
def enter
  mutex = RedisMutex.new('non-blocking', block: 0, expire: 10.minutes)
  if mutex.lock
    begin
      # do something exclusively
    ensure
      mutex.unlock
    end
    render text: 'success!'
  else
    render text: 'failed to acquire lock!'
  end
end
```

Macro-style definition
----------------------

If you want to wrap an entire method into a critical section, you can use the macro-style definition. The locking scope
will be `TheClass#method` and only one method can run at any given time.

If you give a proc object to the `after_failure` option, it will get called after locking attempt failed.

```ruby
class JobController < ApplicationController
  include RedisMutex::Macro
  auto_mutex :run, block: 0, after_failure: lambda { render text: 'failed to acquire lock!' }

  def run
    # do something exclusively
    render text: 'success!'
  end
end
```

Also you can specify method arguments with the `on` option. The following creates a mutex key named `ItunesVerifier#perform:123456`, so that the same method can run in parallel as long as the `transaction_id` is different.

```ruby
class ItunesVerifier
  include Sidekiq::Worker
  include RedisMutex::Macro
  auto_mutex :perform, on: [:transaction_id]

  def perform(transaction_id)
    ...
  end
end
```
