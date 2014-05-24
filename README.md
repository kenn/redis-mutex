Redis Mutex
===========

[![Build Status](https://secure.travis-ci.org/kenn/redis-mutex.png)](http://travis-ci.org/kenn/redis-mutex)

Distrubuted mutex in Ruby using Redis. Supports both **blocking** and **non-blocking** semantics.

The idea was taken from [the official SETNX doc](http://redis.io/commands/setnx).

Synopsis
--------

In the following example, only one thread / process / server can enter the locked block at one time.

```ruby
Redis::Mutex.with_lock(:your_lock_name) do
  # do something exclusively
end
```

or

```ruby
mutex = Redis::Mutex.new(:your_lock_name)
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

Changes in v2.0
---------------

* **Exception-based control flow**: Added `lock!` and `unlock!`, which raises an exception when fails to acquire a lock. Raises `Redis::Mutex::LockError` and `Redis::Mutex::UnlockError` respectively.
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
Redis::Mutex.default_redis = Redis.new(:host => 'localhost')
```

You can also use a `Redis` object when using the `Redis::Mutex`,
passing a `:redis` value in the options hash:


```Ruby
Redis::Mutex.with_lock("lock-key", :redis => Redis.new(:host => 'localhost')) do
    # Do something
end
```

Or:

```Ruby
Redis::Mutex.new("lock-key", :redis => Redis.new(:host => 'localhost')).with_lock do
    # Do Something
end
```

There are a number of methods:

```ruby
mutex = Redis::Mutex.new(key, options)    # Configure a mutex lock
mutex.lock                                # Try to acquire the lock, returns false when failed
mutex.lock!                               # Try to acquire the lock, raises exception when failed
mutex.unlock                              # Try to release the lock, returns false when failed
mutex.unlock!                             # Try to release the lock, raises exception when failed
mutex.locked?                             # Find out if resource already locked
mutex.with_lock                           # Try to acquire the lock, execute the block, then return the value of the block.
                                          # Raises exception when failed to acquire the lock.

Redis::Mutex.sweep                        # Remove all expired locks
Redis::Mutex.with_lock(key, options)      # Shortcut to new + with_lock
```

The key argument can be symbol, string, or any Ruby objects that respond to `id` method, where the key is automatically set as
`TheClass:id`. For any given key, `Redis::Mutex:` prefix will be automatically prepended. For instance, if you pass a `Room`
object with id of `123`, the actual key in Redis will be `Redis::Mutex:Room:123`. The automatic prefixing and instance binding
is the feature of `Redis::Classy` - for more internal details, refer to [Redis Classy](https://github.com/kenn/redis-classy).

The initialize method takes several options.

```ruby
:block  => 1    # Specify in seconds how long you want to wait for the lock to be released.
                # Speficy 0 if you need non-blocking sematics and return false immediately. (default: 1)
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
    Redis::Mutex.with_lock(@room) do    # key => "Room:123"
      # do something exclusively
    end
    render text: 'success!'
  rescue Redis::Mutex::LockError
    render text: 'failed to acquire lock!'
  end
end
```

Note that you need to explicitly call the `unlock` method when you don't use `with_lock` and its block syntax. Also it is recommended to
put the `unlock` method in the `ensure` clause.

```ruby
def enter
  mutex = Redis::Mutex.new('non-blocking', block: 0, expire: 10.minutes)
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
  include Redis::Mutex::Macro
  auto_mutex :run, block: 0, after_failure: lambda { render text: 'failed to acquire lock!' }

  def run
    # do something exclusively
    render text: 'success!'
  end
end
```
