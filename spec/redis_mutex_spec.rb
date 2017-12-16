require 'spec_helper'

SHORT_MUTEX_OPTIONS = { :block => 0.1, :sleep => 0.02 }

describe RedisMutex do
  before do
    RedisClassy.flushdb
  end

  after :all do
    RedisClassy.flushdb
    RedisClassy.quit
  end

  it 'locks the universe' do
    mutex1 = RedisMutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    expect(mutex1.lock).to be_truthy

    mutex2 = RedisMutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    expect(mutex2.lock).to be_falsey
  end

  it 'fails to lock when the lock is taken' do
    mutex1 = RedisMutex.new(:test_lock, SHORT_MUTEX_OPTIONS)

    mutex2 = RedisMutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    expect(mutex2.lock).to be_truthy    # mutex2 beats us to it

    expect(mutex1.lock).to be_falsey   # fail
  end

  it 'unlocks only once' do
    mutex = RedisMutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    expect(mutex.lock).to be_truthy

    expect(mutex.unlock).to be_truthy   # successfully released the lock
    expect(mutex.unlock).to be_falsey  # the lock no longer exists
  end

  it 'prevents accidental unlock from outside' do
    mutex1 = RedisMutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    expect(mutex1.lock).to be_truthy

    mutex2 = RedisMutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    expect(mutex2.unlock).to be_falsey
  end

  it 'sets expiration' do
    start = Time.now
    expires_in = 10
    mutex = RedisMutex.new(:test_lock, :expire => expires_in)
    mutex.with_lock do
      expect(mutex.get.to_f).to be_within(1.0).of((start + expires_in).to_f)
    end
    expect(mutex.get).to be_nil   # key should have been cleaned up
  end

  it 'overwrites a lock when existing lock is expired' do
    # stale lock from the far past
    RedisMutex.on(:test_lock).set(Time.now - 60)

    mutex = RedisMutex.new(:test_lock)
    expect(mutex.lock).to be_truthy
  end

  it 'fails to unlock the key if it took too long past expiration' do
    mutex = RedisMutex.new(:test_lock, :expire => 0.1, :block => 0)
    expect(mutex.lock).to be_truthy
    sleep 0.2   # lock expired

    # someone overwrites the expired lock
    mutex2 = RedisMutex.new(:test_lock, :expire => 10, :block => 0)
    expect(mutex2.lock).to be_truthy

    mutex.unlock
    expect(mutex.get).not_to be_nil   # lock should still be there
  end

  it 'ensures unlocking when something goes wrong in the block' do
    mutex = RedisMutex.new(:test_lock)
    begin
      mutex.with_lock do
        raise "Something went wrong!"
      end
    rescue RuntimeError
      expect(mutex.get).to be_nil
    end
  end

  it 'resets locking state on reuse' do
    mutex = RedisMutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    expect(mutex.lock).to be_truthy
    expect(mutex.lock).to be_falsey
  end

  it 'tells about lock\'s state' do
    mutex = RedisMutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    mutex.lock

    expect(mutex).to be_locked

    mutex.unlock
    expect(mutex).not_to be_locked
  end

  it 'tells that resource is not locked when lock is expired' do
    mutex = RedisMutex.new(:test_lock, :expire => 0.1)
    mutex.lock

    sleep 0.2 # lock expired now

    expect(mutex).not_to be_locked
  end

  it 'returns value of block' do
    expect(RedisMutex.with_lock(:test_lock) { :test_result }).to eq(:test_result)
  end

  it 'requires block for #with_lock' do
    expect { RedisMutex.with_lock(:test_lock) }.to raise_error(LocalJumpError) #=> no block given (yield)
  end

  it 'raises LockError if lock not obtained' do
    expect { RedisMutex.lock!(:test_lock, SHORT_MUTEX_OPTIONS) }.to_not raise_error
    expect { RedisMutex.lock!(:test_lock, SHORT_MUTEX_OPTIONS) }.to raise_error(RedisMutex::LockError)
  end

  it 'raises UnlockError if lock not obtained' do
    mutex = RedisMutex.new(:test_lock)
    expect(mutex.lock).to be_truthy
    expect(mutex.unlock).to be_truthy
    expect { mutex.unlock! }.to raise_error(RedisMutex::UnlockError)
  end

  it 'raises AssertionError when block is given to #lock' do
    # instance method
    mutex = RedisMutex.new(:test_lock)
    expect { mutex.lock {} }.to raise_error(RedisMutex::AssertionError)

    # class method
    expect { RedisMutex.lock(:test_lock) {} }.to raise_error(RedisMutex::AssertionError)
  end

  it 'sweeps expired locks' do
    RedisMutex.on(:past).set(Time.now.to_f - 60)
    RedisMutex.on(:present).set(Time.now.to_f)
    RedisMutex.on(:future).set(Time.now.to_f + 60)
    expect(RedisMutex.keys.size).to eq(3)
    expect(RedisMutex.sweep).to eq(2)
    expect(RedisMutex.keys.size).to eq(1)
  end

  describe 'stress test' do
    LOOP_NUM = 1000

    def run(id)
      print "invoked worker #{id}...\n"
      mutex = RedisMutex.new(:test_lock, :expire => 1, :block => 10, :sleep => 0.01)
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

    it 'runs without hiccups' do
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
