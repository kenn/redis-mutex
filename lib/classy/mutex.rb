require 'redis-classy'

class Redis::Classy::Mutex < Redis::Classy
  
  def initialize(object, timeout=10)
    @now = Time.now.to_i
    @expires_at = @now + timeout
    super("#{object.class.name}:#{object.id}")
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

  def self.sweep
    now = Time.now.to_i
    keys = self.keys
    values = self.mget(*keys)

    stale_keys = [].tap do |array|
      keys.each_with_index do |key, i|
        array << key if !values[i].nil? and values[i].to_i <= now
      end
    end

    stale_keys.each do |key|
      self.del(key) if self.getset(key, now + 10).to_i <= now # Make extra sure someone haven't released the lock yet.
    end

    stale_keys.size
  end
end
