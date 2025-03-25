class RedisMutex < RedisClassy
  module ConcurrentMutex
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def concurrent_sweep(*args, **kwargs)
        cumulative_sweep(*args, **kwargs)
      end
    end

    def concurrent_try_lock
      cumulative_try_lock
    end
    def concurrent_locked?(*args, **kwargs)
      cumulative_locked?(*args, **kwargs)
    end
    def concurrent_cleanup_set(*args, **kwargs)
      cumulative_cleanup_set(*args, **kwargs)
    end
    def concurrent_key_count(*args, **kwargs)
      cumulative_key_count(*args, **kwargs)
    end

    def concurrent_unlock(_)
      !!redis.zrem("#{key}:#{type}_set", @unique_key)
    end
  end
end