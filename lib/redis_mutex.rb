class RedisMutex < RedisClassy
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
  autoload :Macro, 'redis_mutex/macro'

  DEFAULT_EXPIRE = 10
  LockError = Class.new(StandardError)
  UnlockError = Class.new(StandardError)
  AssertionError = Class.new(StandardError)

  def initialize(object, options={})
    super(object.is_a?(String) || object.is_a?(Symbol) ? object : "#{object.class.name}:#{object.id}")
    @block = options[:block] || 1
    @sleep = options[:sleep] || 0.1
    @expire = options[:expire] || DEFAULT_EXPIRE
  end

  def lock
    self.class.raise_assertion_error if block_given?
    @locking = false

    if @block > 0
      # Blocking mode
      start_at = Time.now
      while Time.now - start_at < @block
        @locking = true and break if try_lock
        sleep @sleep
      end
    else
      # Non-blocking mode
      @locking = try_lock
    end
    @locking
  end

  def try_lock
    now = Time.now.to_f
    @expires_at = now + @expire                       # Extend in each blocking loop

    until setnx(@expires_at) # loop until succeeded, this is the only place where we can be sure locked key belong to us
      watch do
        if (old_value = get).nil? # try again it's probably free now
          unwatch
          next
        end
        if old_value.to_f > now
          unwatch
          return false # someone else keeps valid lock, leave now
        else # get < now - possibly expired
          # now try to delete expired lock
          return false unless multi { del } # someone else has messed with this key, leave now
          # or try again
        end
      end
    end
    return true
  end

  # Returns true if resource is locked. Note that nil.to_f returns 0.0
  def locked?
    get.to_f > Time.now.to_f
  end

  def unlock(force = false)
    # Since it's possible that the operations in the critical section took a long time,
    # we can't just simply release the lock. The unlock method checks if @expires_at
    # remains the same, and do not release when the lock timestamp was overwritten.

    watch do
      if get == @expires_at.to_s || force
        multi do
          # Redis#del with a single key returns '1' or nil
          !!del
        end
      else
        unwatch
        false
      end
    end
  end

  def with_lock
    if lock!
      begin
        @result = yield
      ensure
        unlock
      end
    end
    @result
  end

  def lock!
    lock or raise LockError, "failed to acquire lock #{key.inspect}"
  end

  def unlock!(force = false)
    unlock(force) or raise UnlockError, "failed to release lock #{key.inspect}"
  end

  class << self
    def sweep
      return 0 if (all_keys = keys).empty?

      now = Time.now.to_f
      values = mget(*all_keys)

      expired_keys = all_keys.zip(values).select do |key, time|
        time && time.to_f <= now
      end

      expired_keys.each do |key, _|
        # Make extra sure that anyone haven't extended the lock
        del(key) if getset(key, now + DEFAULT_EXPIRE).to_f <= now
      end

      expired_keys.size
    end

    def lock(object, options = {})
      raise_assertion_error if block_given?
      new(object, options).lock
    end

    def lock!(object, options = {})
      new(object, options).lock!
    end

    def with_lock(object, options = {}, &block)
      new(object, options).with_lock(&block)
    end

    def raise_assertion_error
      raise AssertionError, 'block syntax has been removed from #lock, use #with_lock instead'
    end
  end
end
