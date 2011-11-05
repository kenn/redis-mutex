Redis Mutex
===========

Distrubuted mutex in Ruby using Redis. Supports both **blocking** and **non-blocking** semantics.

The idea was taken from [the official SETNX doc](http://redis.io/commands/setnx).

Synopsis
--------

In the following example, only one thread / process / server can enter the locked block at one time.

```ruby
Redis::Mutex.lock(:your_lock_name)
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
  puts "failed to obtain lock!"
end
```

By default, while one is holding a lock, others wait **1 second** in total, polling **every 100ms** to see if the lock was released.
When 1 second has passed, the lock method returns `false` and others give up. Note that if your job runs longer than **10 seconds**,
the lock will be automatically removed to avoid a deadlock situation in case your job is dead without releasing the lock. Also note
that you can configure any of these timing values, as explained later.

Or if you want to immediately receive `false` on an unsuccessful locking attempt, you can change the mutex mode to **non-blocking** mode.

Install
-------

    gem install redis-mutex

Usage
-----

In Gemfile:

```ruby
gem "redis-mutex"
```

Register the Redis server: (e.g. in `config/initializers/redis_mutex.rb` for Rails)

```ruby
Redis::Classy.db = Redis.new(:host => 'localhost')
```

Note that Redis Mutex uses the `redis-classy` gem internally to organize keys in an isolated namespace.

There are four methods - `new`, `lock`, `unlock` and `sweep`:

```ruby
mutex = Redis::Mutex.new(key, options)    # Configure a mutex lock
mutex.lock                                # Try to obtain the lock
mutex.unlock                              # Release the lock if it's not expired
Redis::Mutex.sweep                        # Forcibly remove all locks

Redis::Mutex.lock(key, options)           # Shortcut to new + lock
```

The key argument can be any Ruby objects that respond to `id` method, where the key is automatically set as `TheClass:id`,
or pass any string or symbol. The `Redis::Mutex:` prefix will be automatically prepended to the given key name. For instance,
if you pass a `Room` object with id of `123`, the actual key in Redis will be `Redis::Mutex:Room:123`. The automatic prefixing
and instance binding is the feature of `Redis::Classy` - for more internal details, refer to [Redis Classy](https://github.com/kenn/redis-classy).

The initialize method takes several options.

```ruby
:block  => 1    # Specify in seconds how long you want to wait for the lock to be released.
                # Speficy 0 if you need non-blocking sematics and return false immediately. (default: 1)
:sleep  => 0.1  # Specify in seconds how long the polling interval should be when :block is given.
                # It is recommended that you do NOT go below 0.01. (default: 0.1)
:expire => 10   # Specify in seconds when the lock should forcibly be removed when something went wrong
                # with the one who held the lock. (default: 10)
```

The lock method returns `true` when the lock has been successfully obtained, or returns `false` when the attempts
failed after the seconds specified with **:block**. It is set to **non-blocking** mode and immediately returns `false`
when 0 is given to **:block**.

In the following Rails example, only one request can enter to a given room.

```ruby
class RoomController < ApplicationController
  before_filter { @room = Room.find(params[:id]) }
  
  def enter
    success = Redis::Mutex.lock(@room) do    # key => "Room:123"
      # do something exclusively
    end
    render :text => success ? 'success!' : 'failed to obtain lock!'
  end
end
```

Note that you need to explicitly call the unlock method unless you don't use the block syntax, and it is recommended to
put the `unlock` method in the `ensure` clause unless you're sure your code won't raise any exception.

```ruby
def enter
  mutex = Redis::Mutex.new('non-blocking', :block => 0, :expire => 10.minutes)
  if mutex.lock
    begin
      # do something exclusively
    ensure
      mutex.unlock
    end
    render :text => 'success!'
  else
    render :text => 'failed to obtain lock!'
  end
end
```

Macro-style definition
----------------------

If you want to put an entire method into a critical section, you can use the macro-style definition. The locking scope
will be `TheClass#method` and only one method can run at any given time.

```ruby
class JobController < ApplicationController
  include Redis::Mutex::Macro
  auto_mutex :run, :block => 0, :after_failure => lambda { render :text => "failed!" }
  
  def run
    # do something exclusively
    render :text => "success!"
  end
end
```
