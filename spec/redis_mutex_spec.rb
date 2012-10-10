require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe Redis::Mutex do
  before do
    Redis::Classy.flushdb
    @short_mutex_options = { :block => 0.1, :sleep => 0.02 }
  end

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
    mutex = Redis::Mutex.new(:test_lock, @short_mutex_options)

    # someone beats us to it
    mutex2 = Redis::Mutex.new(:test_lock, @short_mutex_options)
    mutex2.lock

    mutex.lock.should be_false    # should not have the lock
    mutex.get.should_not be_nil   # lock value should still be set
  end

  it "should not remove the key if lock is held past expiration" do
    mutex = Redis::Mutex.new(:test_lock, :expire => 0.1, :block => 0)
    mutex.lock.should be_true
    sleep 0.2   # lock expired

    # someone overwrites the expired lock
    mutex2 = Redis::Mutex.new(:test_lock, :expire => 10, :block => 0)
    mutex2.lock.should be_true

    mutex.unlock
    mutex.get.should_not be_nil   # lock should still be there
  end

  it "should ensure unlock when something goes wrong in the block" do
    mutex = Redis::Mutex.new(:test_lock)
    begin
      mutex.lock do
        raise "Something went wrong!"
      end
    rescue
      mutex.locking.should be_false
    end
  end

  it "should reset locking state on reuse" do
    mutex = Redis::Mutex.new(:test_lock, @short_mutex_options)
    mutex.lock.should be_true
    mutex.lock.should be_false
  end

  describe Redis::Mutex::Macro do
    it "should add auto_mutex" do

      class C
        include Redis::Mutex::Macro
        auto_mutex :run_singularly, :block => 0, :after_failure => lambda {|id| return "failure: #{id}" }

        def run_singularly(id)
          sleep 0.1
          return "success: #{id}"
        end
      end

      t1 = Thread.new { C.new.run_singularly(1).should == "success: 1" }
      sleep 0.01 # In most cases t1 wins, but make sure to give it a head start, not exceeding the sleep inside the method
      t2 = Thread.new { C.new.run_singularly(2).should == "failure: 2" }
      t1.join
      t2.join
    end
  end

  describe '::lock!' do
    it 'should not raise error if lock obtained' do
      expect { Redis::Mutex.lock!(:test_lock) }.to_not raise_error
    end

    it 'should return value of block if lock obtained' do
      Redis::Mutex.lock!(:test_lock) { :test_result }.should == :test_result
    end

    it 'should raise error if lock not obtained' do
      Redis::Mutex.lock(:test_lock)
      expect { Redis::Mutex.lock!(:test_lock) }.
        to raise_error(Redis::Mutex::LockNotAcquired)
    end
  end
end
