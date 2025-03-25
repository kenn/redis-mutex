class RedisMutex < RedisClassy
  module ConcurrentMutex
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def concurrent_sweep(...)
        cumulative_sweep(...)
      end
    end

    def concurrent_try_lock
      cumulative_try_lock
    end
    def concurrent_locked?(...)
      cumulative_locked?(...)
    end
    def concurrent_cleanup_set(...)
      cumulative_cleanup_set(...)
    end
    def concurrent_key_count(...)
      cumulative_key_count(...)
    end

    def concurrent_unlock(_)
      !!redis.zrem("#{key}:#{type}_set", @unique_key)
    end
  end
end