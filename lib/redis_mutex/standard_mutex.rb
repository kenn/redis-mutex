class RedisMutex < RedisClassy
  module StandardMutex
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def standard_sweep(now, all_keys)
        expired_keys = all_keys.select do |key, time|
          time.to_f <= now
        end

        expired_keys.each do |redis_key, _|
          # Make extra sure that anyone haven't extended the lock
          delete_key(redis_key) if getset(redis_key, now + DEFAULT_EXPIRE).to_f <= now
        end

        expired_keys.size
      end
    end

    def standard_try_lock
      now = Time.now.to_f
      @expires_at = now + @expire                       # Extend in each blocking loop

      begin
        if setnx(@expires_at)
          return true               # Success, the lock has been acquired
        end
      end until old_value = get                         # Repeat if unlocked before get

      return false if old_value.to_f > now              # Check if the lock is still effective

      # The lock has expired but wasn't released... BAD!
      if getset(@expires_at).to_f <= now
        return true     # Success, we acquired the previously expired lock
      end
      return false # Dammit, it seems that someone else was even faster than us to remove the expired lock!
    end

    def standard_locked?(_ = {})
      get.to_f > Time.now.to_f
    end

    def standard_unlock(force = false)
      # Since it's possible that the operations in the critical section took a long time,
      # we can't just simply release the lock. The unlock method checks if @expires_at
      # remains the same, and do not release when the lock timestamp was overwritten.

      if get == @expires_at.to_s or force
        # Redis#unlink or Redis#del with a single key returns '1' or nil
        !!delete_key
      else
        false
      end
    end

    def standard_key_count(_ = {})
      exists? ? 1 : 0
    end

    def standard_cleanup_set(_ = {})
      nil
    end
  end
end
