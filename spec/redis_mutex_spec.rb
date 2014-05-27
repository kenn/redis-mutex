require 'spec_helper'

SHORT_MUTEX_OPTIONS = { :block => 0.1, :sleep => 0.02 }

class C
  include Redis::Mutex::Macro
  auto_mutex :run_singularly, :block => 0, :after_failure => lambda {|id| return "failure: #{id}" }

  def run_singularly(id)
    sleep 0.1
    return "success: #{id}"
  end

  auto_mutex :run_singularly_on_args, :block => 0, :on => [:id, :bar], :after_failure => lambda {|id, *others| return "failure: #{id}" }
  def run_singularly_on_args(id, foo, bar)
    sleep 0.1
    return "success: #{id}"
  end

  auto_mutex :run_singularly_on_keyword_args, :block => 0, :on => [:id, :bar], :after_failure => lambda {|id:, **others| return "failure: #{id}" }
  def run_singularly_on_keyword_args(id:, foo:, bar:)
    sleep 0.1
    return "success: #{id}"
  end
end

describe Redis::Mutex do
  before do
    Redis::Classy.flushdb
  end

  after :all do
    Redis::Classy.flushdb
    Redis::Classy.quit
  end

  it 'locks the universe' do
    mutex1 = Redis::Mutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    mutex1.lock.should be_true

    mutex2 = Redis::Mutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    mutex2.lock.should be_false
  end

  it 'fails to lock when the lock is taken' do
    mutex1 = Redis::Mutex.new(:test_lock, SHORT_MUTEX_OPTIONS)

    mutex2 = Redis::Mutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    mutex2.lock.should be_true    # mutex2 beats us to it

    mutex1.lock.should be_false   # fail
  end

  it 'unlocks only once' do
    mutex = Redis::Mutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    mutex.lock.should be_true

    mutex.unlock.should be_true   # successfully released the lock
    mutex.unlock.should be_false  # the lock no longer exists
  end

  it 'prevents accidental unlock from outside' do
    mutex1 = Redis::Mutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    mutex1.lock.should be_true

    mutex2 = Redis::Mutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    mutex2.unlock.should be_false
  end

  it 'sets expiration' do
    start = Time.now
    expires_in = 10
    mutex = Redis::Mutex.new(:test_lock, :expire => expires_in)
    mutex.with_lock do
      mutex.get.to_f.should be_within(1.0).of((start + expires_in).to_f)
    end
    mutex.get.should be_nil   # key should have been cleaned up
  end

  it 'overwrites a lock when existing lock is expired' do
    # stale lock from the far past
    Redis::Mutex.set(:test_lock, Time.now - 60)

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
    mutex.get.should_not be_nil   # lock should still be there
  end

  it 'ensures unlocking when something goes wrong in the block' do
    mutex = Redis::Mutex.new(:test_lock)
    begin
      mutex.with_lock do
        raise "Something went wrong!"
      end
    rescue RuntimeError
      mutex.get.should be_nil
    end
  end

  it 'resets locking state on reuse' do
    mutex = Redis::Mutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
    mutex.lock.should be_true
    mutex.lock.should be_false
  end

  it 'tells about lock\'s state' do
    mutex = Redis::Mutex.new(:test_lock, SHORT_MUTEX_OPTIONS)
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
    expect { Redis::Mutex.lock!(:test_lock, SHORT_MUTEX_OPTIONS) }.to_not raise_error
    expect { Redis::Mutex.lock!(:test_lock, SHORT_MUTEX_OPTIONS) }.to raise_error(Redis::Mutex::LockError)
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
    Redis::Mutex.set(:past, Time.now.to_f - 60)
    Redis::Mutex.set(:present, Time.now.to_f)
    Redis::Mutex.set(:future, Time.now.to_f + 60)
    Redis::Mutex.keys.size.should == 3
    Redis::Mutex.sweep.should == 2
    Redis::Mutex.keys.size.should == 1
  end

  describe Redis::Mutex::Macro do
    let(:object_arg) { Object.new }

    it 'adds auto_mutex' do
      t1 = Thread.new { C.new.run_singularly(1).should == "success: 1" }
      # In most cases t1 wins, but make sure to give it a head start,
      # not exceeding the sleep inside the method.
      sleep 0.01
      t2 = Thread.new { C.new.run_singularly(2).should == "failure: 2" }
      t1.join
      t2.join
    end

    it 'adds auto_mutex on different args' do
      t1 = Thread.new { C.new.run_singularly_on_args(1, :'2', object_arg).should == "success: 1" }
      # In most cases t1 wins, but make sure to give it a head start,
      # not exceeding the sleep inside the method.
      sleep 0.01
      t2 = Thread.new { C.new.run_singularly_on_args(2, :'2', object_arg).should == "success: 2" }
      t1.join
      t2.join
    end

    it 'adds auto_mutex on same args' do
      t1 = Thread.new { C.new.run_singularly_on_args(1, :'2', object_arg).should == "success: 1" }
      # In most cases t1 wins, but make sure to give it a head start,
      # not exceeding the sleep inside the method.
      sleep 0.01
      t2 = Thread.new { C.new.run_singularly_on_args(1, :'2', object_arg).should == "failure: 1" }
      t1.join
      t2.join
    end

    it 'adds auto_mutex on different keyword args' do
      t1 = Thread.new { C.new.run_singularly_on_keyword_args(id: 1, foo: :'2', bar: object_arg).should == "success: 1" }
      # In most cases t1 wins, but make sure to give it a head start,
      # not exceeding the sleep inside the method.
      sleep 0.01
      t2 = Thread.new { C.new.run_singularly_on_keyword_args(id: 2, foo: :'2', bar: object_arg).should == "success: 2" }
      t1.join
      t2.join
    end

    it 'adds auto_mutex on same keyword args' do
      t1 = Thread.new { C.new.run_singularly_on_keyword_args(id: 1, foo: :'2', bar: object_arg).should == "success: 1" }
      # In most cases t1 wins, but make sure to give it a head start,
      # not exceeding the sleep inside the method.
      sleep 0.01
      t2 = Thread.new { C.new.run_singularly_on_keyword_args(id: 1, foo: :'2', bar: object_arg).should == "failure: 1" }
      t1.join
      t2.join
    end

    it 'raise exception if there is no such argument' do
      expect {
        class C
          auto_mutex :run_without_such_args, :block => 0, :on => [:missing_arg]
          def run_without_such_args(id)
            return "success: #{id}"
          end
        end
      }.to raise_error(ArgumentError) { |error|
        expect(error.message).to eq 'You are trying to lock on unknown arguments: missing_arg'
      }

    end
  end

  describe 'stress test' do
    LOOP_NUM = 1000

    def run(id)
      print "invoked worker #{id}...\n"
      Redis::Classy.db.client.reconnect
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
