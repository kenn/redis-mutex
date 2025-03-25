class RedisMutex < RedisClassy
  module ConcurrentMutex
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def concurrent_sweep(now, all_keys)
        cumulative_sweep(now, all_keys)
      end
    end

    def concurrent_try_lock
      cumulative_try_lock
    end
    def concurrent_locked?(options = {})
      cumulative_locked?(options)
    end
    def concurrent_cleanup_set(options = {})
      cumulative_cleanup_set(options)
    end
    def concurrent_key_count(options = {})
      cumulative_key_count(options)
    end

    def concurrent_unlock(_)
      !!redis.zrem("#{key}:#{type}_set", @unique_key)
    end
  end
end