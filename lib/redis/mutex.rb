class Redis
  #
  # Options
  #
  # :block  => Specify in seconds how long you want to wait for the lock to be released. Speficy 0
  #            if you need non-blocking sematics and return false immediately. (default: 1)
  # :sleep  => Specify in seconds how long the polling interval should be when :block is given.
  #            It is recommended that you do NOT go below 0.01. (default: 0.1)
  # :expire => Specify in seconds when the lock should forcibly be removed when something went wrong
  #            with the one who held the lock. (default: 10)
  #
  class Mutex < Redis::Classy
    autoload :Macro, 'redis/mutex/macro'

    attr_reader :locking
    DEFAULT_EXPIRE = 10

    def initialize(object, options={})
      super(object.is_a?(String) || object.is_a?(Symbol) ? object : "#{object.class.name}:#{object.id}")
      @block = options[:block] || 1
      @sleep = options[:sleep] || 0.1
      @expire = options[:expire] || DEFAULT_EXPIRE
    end

    def lock
      @locking = false

      if @block > 0
        # Blocking mode
        start_at = Time.now
        while Time.now - start_at < @block
          @locking = true and break if try_lock
          Kernel.sleep @sleep
        end
      else
        # Non-blocking mode
        @locking = try_lock
      end
      success = @locking # Backup

      if block_given? and @locking
        begin
          yield
        ensure
          # Since it's possible that the yielded operation took a long time, we can't just simply
          # Release the lock. The unlock method checks if the expires_at remains the same that you
          # set, and do not release it when the lock timestamp was overwritten.
          unlock
        end
      end

      success
    end

    def try_lock
      now = Time.now.to_f
      @expires_at = now + @expire                             # Extend in each blocking loop
      return true   if self.setnx(@expires_at)                # Success, the lock has been acquired
      return false  if self.get.to_f > now                    # Check if the lock is still effective

      # The lock has expired but wasn't released... BAD!
      return true   if self.getset(@expires_at).to_f <= now   # Success, we acquired the previously expired lock
      return false  # Dammit, it seems that someone else was even faster than us to remove the expired lock!
    end

    def unlock(force=false)
      @locking = false
      self.del if self.get.to_f == @expires_at or force       # Release the lock if it seems to be yours
    end

    class << self
      def to_ary
        
      end
      def sweep
        return 0 if (all_keys = self.keys).empty?

        now = Time.now.to_f
        values = self.mget(*all_keys)

        expired_keys = [].tap do |array|
          all_keys.each_with_index do |key, i|
            array << key if !values[i].nil? and values[i].to_f <= now
          end
        end

        expired_keys.each do |key|
          self.del(key) if self.getset(key, now + DEFAULT_EXPIRE).to_f <= now # Make extra sure that anyone haven't extended the lock
        end

        expired_keys.size
      end

      def lock(object, options={}, &block)
        new(object, options).lock(&block)
      end
    end
  end
end
