class RedisMutex < RedisClassy
  module WindowedMutex
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def windowed_sweep(...)
        # windowed mutexes use expire to automatically remove keys
        0
      end
    end

    def windowed_try_lock
      RedisMutex.with_lock(key, limit: 1, expire: @expire, block: 0, sleep: @sleep) do
        if locked?
          false
        else
          begin
            key_was = key
            self.key = "#{key}:#{type}_list"
            lpush(@unique_key)
            expire(@expire, nx: true) # only set expire if it does not have one
          ensure
            self.key = key_was
          end
          true
        end
      end
    rescue RedisMutex::LockError
      # If we can't get the lock, we can't get lock
      false
    end

    def windowed_locked?(...)
      cumulative_locked?(...)
    end

    def windowed_unlock(...)
      cumulative_unlock(...)
    end

    def windowed_key_count(...)
      key_was = key
      self.key = "#{key}:#{type}_list"
      llen
    rescue Redis::BaseError
      0
    ensure
      self.key = key_was
    end

    def windowed_cleanup_set(...)
      nil
    end
  end
end