class RedisMutex < RedisClassy
  module WindowedMutex
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def windowed_sweep(_now, _all_keys)
        # windowed mutexes use expire to automatically remove keys
        0
      end
    end

    def windowed_try_lock
      RedisMutex.with_lock(key, limit: 1, expire: @expire, block: 0, sleep: @sleep) do
        if locked?
          false
        else
          windowed_key = "#{key}:#{type}_list"
          redis.lpush(windowed_key, @unique_key)
          redis.expire(windowed_key, @expire, nx: true) # only set expire if it does not have one
          true
        end
      end
    rescue RedisMutex::LockError
      # If we can't get the lock, we can't get lock
      false
    end

    def windowed_locked?(options = {})
      cumulative_locked?(options)
    end

    def windowed_unlock(force = false)
      cumulative_unlock(force)
    end

    def windowed_key_count(_ = {})
      redis.llen("#{key}:#{type}_list")
    rescue Redis::BaseError
      0
    end

    def windowed_cleanup_set(_ = {})
      nil
    end
  end
end
