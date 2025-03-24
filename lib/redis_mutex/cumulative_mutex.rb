class RedisMutex < RedisClassy
  module CumulativeMutex
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def cumulative_sweep(now, all_keys)
        return 0 if all_keys.nil? || all_keys.empty?

        multi do |pipeline|
          all_keys.each do |redis_key|
            pipeline.zremrangebyscore(redis_key, '-inf', "#{now.to_i - DEFAULT_EXPIRE})")
          end
        end
      end
    end

    def cumulative_try_lock
      RedisMutex.with_lock(key, limit: 1, expire: @expire, block: 0, sleep: @sleep) do
        now = Time.now.to_i
        if locked?(now: now)
          false
        else
          begin
            key_was = key
            self.key = "#{key}:#{type}_set"
            zadd(now, @unique_key)
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

    def cumulative_locked?(now: Time.now.to_i, limit: @limit)
      key_count(now: now) >= limit
    end

    def cumulative_unlock(force = false)
      if force
        !!unlink
      else
        false
      end
    end

    def cumulative_key_count(now: Time.now.to_i)
      key_was = key
      self.key = "#{key}:#{type}_set"
      zcount(now - @expire, now)
    rescue Redis::BaseError
      0
    ensure
      self.key = key_was
    end

    def cumulative_cleanup_set(now: Time.now.to_i)
      key_was = key
      self.key = "#{key_was}:#{type}_set"
      # Any set members with a score lower than the current time minus the expire time are no longer needed
      # This is to optimize the key_count too O(log(N)) and the cleanup which is O(log(N)+M)
      # So cleanup should be run as often as possible
      zremrangebyscore('-inf', "(#{now - @expire}")
    rescue RedisMutex::LockError
      nil
    ensure
      self.key = key_was
    end
  end
end