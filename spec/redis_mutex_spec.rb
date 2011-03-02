require 'spec_helper'

describe Redis::Mutex do
  after do
    Redis::Classy.flushdb
  end

  it "should set the value to the expiration" do
    start = Time.now
    expires_in = 10
    mutex = Redis::Mutex.new(:test_lock, :expire => expires_in)
    mutex.lock do
      mutex.get.to_f.should be_within(1.0).of((start + expires_in).to_f)
    end
    # key should have been cleaned up
    mutex.get.should be_nil
  end

  it "should get a lock when existing lock is expired" do
    mutex = Redis::Mutex.new(:test_lock)
    # locked in the far past
    Redis::Mutex.set(:test_lock, Time.now - 60)

    mutex.lock.should be_true
    mutex.get.should_not be_nil
    mutex.unlock
    mutex.get.should be_nil
  end

  it "should not get a lock when existing lock is still effective" do
    mutex = Redis::Mutex.new(:test_lock, :block => 0.2)

    # someone beats us to it
    mutex2 = Redis::Mutex.new(:test_lock, :block => 0.2)
    mutex2.lock

    mutex.lock.should be_false    # should not have the lock
    mutex.get.should_not be_nil   # lock value should still be set
  end

  it "should not remove the key if lock is held past expiration" do
    mutex = Redis::Mutex.new(:test_lock, :expire => 0.1, :block => 0)
    mutex.lock
    sleep 0.2   # lock expired

    # someone overwrites the expired lock
    mutex2 = Redis::Mutex.new(:test_lock, :expire => 10, :block => 0)
    mutex2.lock.should be_true

    mutex.unlock
    mutex.get.should_not be_nil   # lock should still be there
  end
end
