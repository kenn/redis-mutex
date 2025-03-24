class RedisMutex < RedisClassy
  module ConcurrentMutex
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def cumulative_sweep(...)
        concurrent_sweep(...)
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
      key_was = key
      self.key = "#{key}:#{type}_set"
      !!zrem(@unique_key)
    ensure
      self.key = key_was
    end
  end
end