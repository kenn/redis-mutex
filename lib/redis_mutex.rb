require 'securerandom'

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
  # :limit  => Specify how many times the provided block can be executed. (default: 1)
  #            When type is :cumulative or :windowed it means executions over the expire period
  #            When type is :concurrent it means concurrent executions
  # :type   => Specify the type of the mutex. (default: :concurrent) [:cumulative, :windowed, :concurrent]
  #            :concurrent + limit = 1 is the same as the original RedisMutex
  #            :concurrent is to limit parallel or concurrent executions of the block
  #            :cumulative is to limit total executions of the block over the past expire seconds
  #            :windowed is to limit executions of the block in a window that represents expire full seconds
  #
  autoload :Macro, 'redis_mutex/macro'
  autoload :StandardMutex, 'redis_mutex/standard_mutex'
  autoload :CumulativeMutex, 'redis_mutex/cumulative_mutex'
  autoload :ConcurrentMutex, 'redis_mutex/concurrent_mutex'
  autoload :WindowedMutex, 'redis_mutex/windowed_mutex'

  include StandardMutex
  include CumulativeMutex
  include WindowedMutex
  include ConcurrentMutex

  DEFAULT_EXPIRE = 10
  LockError = Class.new(StandardError)
  UnlockError = Class.new(StandardError)
  AssertionError = Class.new(StandardError)

  def initialize(object, options={})
    super(object.is_a?(String) || object.is_a?(Symbol) ? object : "#{object.class.name}:#{object.id}")
    @block = options[:block]&.to_f || 1
    @sleep = options[:sleep]&.to_f || 0.1
    @expire = options[:expire]&.to_i || DEFAULT_EXPIRE
    @limit = options[:limit]&.to_i || 1
    @type = options[:type]&.to_sym || :concurrent
    @unique_key = SecureRandom.uuid.to_s
    raise ArgumentError, "Unknown type: #{@type}" unless %i[cumulative windowed concurrent].include?(@type)
  end

  def type
    case @type
    when :cumulative then :cumulative
    when :windowed then :windowed
    when :concurrent
      @limit == 1 ? :standard : :concurrent
    end
  end

  def lock
    self.class.raise_assertion_error if block_given?
    @locking = false
    cleanup_set

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

    cleanup_set
    @locking
  end

  def try_lock
    public_send("#{type}_try_lock")
  end

  # Returns true if resource is locked. Note that nil.to_f returns 0.0
  def locked?(now: Time.now.to_i, limit: @limit)
    public_send("#{type}_locked?", now: now, limit: limit)
  end

  def unlock(force = false)
    public_send("#{type}_unlock", force)
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

  def cleanup_set(now: Time.now.to_i)
    public_send("#{type}_cleanup_set", now: now)
  end

  def key_count(now: Time.now.to_i)
    public_send("#{type}_key_count", now: now)
  end

  class << self
    def sweep
      all_redis_mutex_keys = all_keys
      now = Time.now.to_f
      total = 0
      total += standard_sweep(now, all_redis_mutex_keys[:standard])
      total += cumulative_sweep(now, all_redis_mutex_keys[:cumulative])
      total += windowed_sweep(now, all_redis_mutex_keys[:windowed])
      total += concurrent_sweep(now, all_redis_mutex_keys[:concurrent])

      total
    end

    def all_keys
      return [] if (all_keys = scan_each.to_a).empty?

      all_keys.zip(mget(*all_keys)).each_with_object(Hash.new { |h, k| h[k] = [] }) do |hash, (key, value)|
        if value.nil?
          if key.end_with?(':cumulative_set')
            hash[:cumulative] << key
          elsif key.end_with?(':windowed_list')
            hash[:windowed] << key
          elsif key.end_with?(':concurrent_set')
            hash[:concurrent] << key
          end
        else
          hash[:standard] << [key, value]
        end
        hash
      end
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
