class Redis
  #
  # Redis::Mutex options
  #
  # :block  => Specify in seconds how long you want to wait for the lock to be released. Speficy 0
  #            if you need non-blocking sematics and return false immediately. (default: 1)
  # :sleep  => Specify in seconds how long the polling interval should be when :block is given.
  #            It is recommended that you do NOT go below 0.01. (default: 0.1)
  # :expire => Specify in seconds when the lock should forcibly be removed when something went wrong
  #            with the one who held the lock. (in seconds, default: 10)
  #
  class Mutex < Redis::Classy

    DEFAULT_EXPIRE = 10
    attr_accessor :options

    def initialize(object, options={})
      super(object.is_a?(String) || object.is_a?(Symbol) ? object : "#{object.class.name}:#{object.id}")
      @options = options
      @options[:block] ||= 1
      @options[:sleep] ||= 0.1
      @options[:expire] ||= DEFAULT_EXPIRE
    end

    def lock
      if @options[:block] > 0
        start_at = Time.now
        success = false
        while Time.now - start_at < @options[:block]
          success = true and break if try_lock
          sleep @options[:sleep]
        end
      else
        # Non-blocking
        success = try_lock
      end

      if block_given? and success
        yield
        # Since it's possible that the yielded operation took a long time, we can't just simply
        # Release the lock. The unlock method checks if the expires_at remains the same that you
        # set, and do not release it when the lock timestamp was overwritten.
        unlock
      end

      success
    end

    def try_lock
      now = Time.now.to_f
      @expires_at = now + @options[:expire]               # Extend in each blocking loop
      return true   if setnx(@expires_at)                 # Success, the lock has been acquired
      return false  if get.to_f > now                     # Check if the lock is still effective

      # The lock has expired but wasn't released... BAD!
      return true   if getset(@expires_at).to_f <= now    # Success, we acquired the previously expired lock
      return false  # Dammit, it seems that someone else was even faster than us to remove the expired lock!
    end

    def unlock(force=false)
      del if get.to_f == @expires_at or force   # Release the lock if it seems to be yours
    end

    def self.sweep
      return 0 if (all_keys = keys).empty?

      now = Time.now.to_f
      values = mget(*all_keys)

      expired_keys = [].tap do |array|
        all_keys.each_with_index do |key, i|
          array << key if !values[i].nil? and values[i].to_f <= now
        end
      end

      expired_keys.each do |key|
        del(key) if getset(key, now + DEFAULT_EXPIRE).to_f <= now # Make extra sure that anyone haven't extended the lock
      end

      expired_keys.size
    end
  end
end
