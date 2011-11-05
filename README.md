Redis Mutex
===========

Distrubuted mutex in Ruby using Redis. Supports both **blocking** and **non-blocking** semantics.

The idea was taken from [the official SETNX doc](http://redis.io/commands/setnx).

Synopsis
--------

In the following example, only one thread / process / server can enter the locked block at one time.

```ruby
mutex = Redis::Mutex.new(:your_lock_name)
mutex.lock do
  # do something exclusively
end
```

By default, when one is holding a lock, others wait **1 second** in total, polling **every 100ms** to see if the lock was released.
When 1 second has passed, the lock method returns `false`.

If you want to immediately receive `false` on an unsuccessful locking attempt, you can configure the mutex to work in the non-blocking mode, as explained later.

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

Note that Redis Mutex uses the `redis-classy` gem internally.

There are four methods - `new`, `lock`, `unlock` and `sweep`:

```ruby
mutex = Redis::Mutex.new(key, options)
mutex.lock
mutex.unlock
Redis::Mutex.sweep
```

For the key, it takes any Ruby objects that respond to :id, where the key is automatically set as "TheClass:id",
or pass any string or symbol.

Also the initialize method takes several options.

```ruby
:block  => 1    # Specify in seconds how long you want to wait for the lock to be released.
                # Speficy 0 if you need non-blocking sematics and return false immediately. (default: 1)
:sleep  => 0.1  # Specify in seconds how long the polling interval should be when :block is given.
                # It is recommended that you do NOT go below 0.01. (default: 0.1)
:expire => 10   # Specify in seconds when the lock should forcibly be removed when something went wrong
                # with the one who held the lock. (default: 10)
```

The lock method returns `true` when the lock has been successfully obtained, or returns `false` when the attempts
failed after the seconds specified with **:block**. It immediately returns `false` when 0 is given to **:block**.

Here's a sample usage in a Rails app:

```ruby
class RoomController < ApplicationController
  def enter
    @room = Room.find(params[:id])

    mutex = Redis::Mutex.new(@room)   # key => "Room:123"
    mutex.lock do
      # do something exclusively
    end
  end
end
```

Note that you need to explicitly call the unlock method unless you don't use the block syntax.

In the following example, 

```ruby
def enter
  mutex = Redis::Mutex.new('non-blocking', :block => 0, :expire => 10.minutes)
  mutex.lock
  # do something exclusively
  mutex.unlock
rescue
  mutex.unlock
  raise
end
```

Also note that, internally, the actual key is structured in the following form:

```ruby
 Redis.new.keys
 => ["Redis::Mutex:Room:111", "Redis::Mutex:Room:112", ... ]
```

The automatic prefixing and binding is the feature of `Redis::Classy`.
For more internal details, refer to [Redis Classy](https://github.com/kenn/redis-classy).
