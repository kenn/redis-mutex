class Redis::Classy::Mutex < Redis::Classy

  TIMEOUT = 10

  def initialize(object, timeout=TIMEOUT)
    @now = Time.now.to_i
    @expires_at = @now + timeout
    super(object.is_a?(String) ? object : "#{object.class.name}:#{object.id}")
  end

  def lock
    return true   if self.setnx(@expires_at)  # Success, the lock was acquired
    return false  if self.get.to_i > @now     # Failure, someone took the　lock and it is still effective

    # The lock has expired but wasn't released... BAD!
    return true   if self.getset(@expires_at).to_i <= @now   # Success, we acquired the previously expired lock!
    return false  # Dammit, it seems that someone else was even faster than us to acquire this lock.
  end

  def unlock
    self.del      if self.get.to_i == @expires_at   # Release the lock if it seems to be yours.
    true
  end

  def self.sweep(timeout=TIMEOUT)
    now = Time.now.to_i
    keys = self.keys

    return 0 if keys.empty?

    values = self.mget(*keys)

    expired_keys = [].tap do |array|
      keys.each_with_index do |key, i|
        array << key if !values[i].nil? and values[i].to_i <= now
      end
    end

    expired_keys.each do |key|
      self.del(key) if self.getset(key, now + timeout).to_i <= now # Make extra sure someone haven't released the lock yet.
    end

    expired_keys.size
  end
end
