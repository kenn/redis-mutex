require 'spec_helper'

class C
  include Redis::Mutex::Macro
  auto_mutex :run_singularly, :block => 0, :after_failure => lambda {|id| return "failure: #{id}" }

  def run_singularly(id)
    sleep 0.1
    return "success: #{id}"
  end
end

describe Redis::Mutex do
  let(:redis) { RSpec.configuration.redis_connection }
  let(:mutex_options) { { :block => 0.1, :sleep => 0.02, :redis => redis } }

  before do
    Redis::Mutex.default_redis.flushdb
  end

  after :all do
    Redis::Mutex.default_redis.flushdb
    Redis::Mutex.default_redis.quit
  end

  it 'locks the universe' do
    mutex1 = Redis::Mutex.new(:test_lock, mutex_options)
    mutex1.lock.should be_true

    mutex2 = Redis::Mutex.new(:test_lock, mutex_options)
    mutex2.lock.should be_false
  end

  it 'fails to lock when the lock is taken' do
    mutex1 = Redis::Mutex.new(:test_lock, mutex_options)

    mutex2 = Redis::Mutex.new(:test_lock, mutex_options)
    mutex2.lock.should be_true    # mutex2 beats us to it

    mutex1.lock.should be_false   # fail
  end

  it 'unlocks only once' do
    mutex = Redis::Mutex.new(:test_lock, mutex_options)
    mutex.lock.should be_true

    mutex.unlock.should be_true   # successfully released the lock
    mutex.unlock.should be_false  # the lock no longer exists
  end

  it 'prevents accidental unlock from outside' do
    mutex1 = Redis::Mutex.new(:test_lock, mutex_options)
    mutex1.lock.should be_true

    mutex2 = Redis::Mutex.new(:test_lock, mutex_options)
    mutex2.unlock.should be_false
  end

  it 'sets expiration' do
    start = Time.now
    expires_in = 10
    mutex = Redis::Mutex.new(:test_lock, :expire => expires_in)
    mutex.with_lock do
      # TODO refactor
      mutex.redis.get(mutex.key).to_f.should be_within(1.0).of((start + expires_in).to_f)
    end
    mutex.redis.get(mutex.key).should be_nil   # key should have been cleaned up
  end

  it 'overwrites a lock when existing lock is expired' do
    # stale lock from the far past
    Redis::Mutex.default_redis.set(:test_lock, Time.now - 60)

    mutex = Redis::Mutex.new(:test_lock)
    mutex.lock.should be_true
  end

  it 'fails to unlock the key if it took too long past expiration' do
    mutex = Redis::Mutex.new(:test_lock, :expire => 0.1, :block => 0)
    mutex.lock.should be_true
    sleep 0.2   # lock expired

    # someone overwrites the expired lock
    mutex2 = Redis::Mutex.new(:test_lock, :expire => 10, :block => 0)
    mutex2.lock.should be_true

    mutex.unlock
    mutex.redis.get(mutex.key).should_not be_nil   # lock should still be there
  end

  it 'ensures unlocking when something goes wrong in the block' do
    mutex = Redis::Mutex.new(:test_lock)
    begin
      mutex.with_lock do
        raise "Something went wrong!"
      end
    rescue RuntimeError
      mutex.redis.get(mutex.key).should be_nil
    end
  end

  it 'resets locking state on reuse' do
    mutex = Redis::Mutex.new(:test_lock, mutex_options)
    mutex.lock.should be_true
    mutex.lock.should be_false
  end

  it 'tells about lock\'s state' do
    mutex = Redis::Mutex.new(:test_lock, mutex_options)
    mutex.lock

    mutex.should be_locked

    mutex.unlock
    mutex.should_not be_locked
  end

  it 'tells that resource is not locked when lock is expired' do
    mutex = Redis::Mutex.new(:test_lock, :expire => 0.1)
    mutex.lock

    sleep 0.2 # lock expired now

    mutex.should_not be_locked
  end

  it 'returns value of block' do
    Redis::Mutex.with_lock(:test_lock) { :test_result }.should == :test_result
  end

  it 'requires block for #with_lock' do
    expect { Redis::Mutex.with_lock(:test_lock) }.to raise_error(LocalJumpError) #=> no block given (yield)
  end

  it 'raises LockError if lock not obtained' do
    expect { Redis::Mutex.lock!(:test_lock, mutex_options) }.to_not raise_error
    expect { Redis::Mutex.lock!(:test_lock, mutex_options) }.to raise_error(Redis::Mutex::LockError)
  end

  it 'raises UnlockError if lock not obtained' do
    mutex = Redis::Mutex.new(:test_lock)
    mutex.lock.should be_true
    mutex.unlock.should be_true
    expect { mutex.unlock! }.to raise_error(Redis::Mutex::UnlockError)
  end

  it 'raises AssertionError when block is given to #lock' do
    # instance method
    mutex = Redis::Mutex.new(:test_lock)
    expect { mutex.lock {} }.to raise_error(Redis::Mutex::AssertionError)

    # class method
    expect { Redis::Mutex.lock(:test_lock) {} }.to raise_error(Redis::Mutex::AssertionError)
  end

  it 'sweeps expired locks' do
    Redis::Mutex.default_redis.set(:past, Time.now.to_f - 60)
    Redis::Mutex.default_redis.set(:present, Time.now.to_f)
    Redis::Mutex.default_redis.set(:future, Time.now.to_f + 60)
    Redis::Mutex.default_redis.keys.size.should eq(3)
    Redis::Mutex.sweep.should eq(2)
    Redis::Mutex.default_redis.keys.size.should eq(1)
  end

  describe Redis::Mutex::Macro do
    it 'adds auto_mutex' do
      t1 = Thread.new { C.new.run_singularly(1).should == "success: 1" }
      # In most cases t1 wins, but make sure to give it a head start,
      # not exceeding the sleep inside the method.
      sleep 0.01
      t2 = Thread.new { C.new.run_singularly(2).should == "failure: 2" }
      t1.join
      t2.join
    end
  end

  describe 'stress test' do
    LOOP_NUM = 1000

    def run(id)
      print "invoked worker #{id}...\n"
      Redis::Mutex.default_redis.client.reconnect
      mutex = Redis::Mutex.new(:test_lock, :expire => 1, :block => 10, :sleep => 0.01)
      result = 0
      LOOP_NUM.times do |i|
        mutex.with_lock do
          result += 1
          sleep rand/100
        end
      end
      print "result for worker #{id}: #{result} successful locks\n"
      exit!(result == LOOP_NUM)
    end

    it 'runs without hiccups' do # TODO uncomment
      begin
        STDOUT.sync = true
        puts "\nrunning stress tests..."
        if pid1 = fork
          # Parent
          if pid2 = fork
            # Parent
            Process.waitall
          else
            # Child 2
            run(2)
          end
        else
          # Child 1
          run(1)
        end
        STDOUT.flush
      rescue NotImplementedError
        puts $!
      end
    end
  end
end
