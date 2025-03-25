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
          redis.zadd("#{key}:#{type}_set", now, @unique_key)
          true
        end
      end
    rescue RedisMutex::LockError
      # If we can't get the lock, we can't get lock
      false
    end

    def cumulative_locked?(options = {})
      key_count(now: options[:now] || Time.now.to_i) >= options[:limit] || @limit
    end

    def cumulative_unlock(force = false)
      if force
        !!delete_key
      else
        false
      end
    end

    def cumulative_key_count(options = {})
      now = options[:now] || Time.now.to_i
      redis.zcount("#{key}:#{type}_set", now - @expire, now)
    rescue Redis::BaseError
      0
    end

    def cumulative_cleanup_set(options = {})
      now = options[:now] || Time.now.to_i
      # Any set members with a score lower than the current time minus the expire time are no longer needed
      # This is to optimize the key_count too O(log(N)) and the cleanup which is O(log(N)+M)
      # So cleanup should be run as often as possible
      redis.zremrangebyscore("#{key}:#{type}_set", '-inf', "(#{now - @expire}")
    end
  end
end