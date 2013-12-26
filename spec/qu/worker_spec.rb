require 'spec_helper'

describe Qu::Worker do
  let(:job) { Qu::Payload.new(:id => '1', :klass => SimpleJob) }

  describe 'queues' do
    it 'should use default if none specified' do
      Qu::Worker.new.queues.should == ['default']
      Qu::Worker.new('default').queues.should == ['default']
      Qu::Worker.new(['default']).queues.should == ['default']
    end
  end

  describe 'work' do
    before do
      Qu.stub(:pop).and_return(job)
    end

    it 'should pop a job' do
      Qu.should_receive(:pop).with(subject).and_return(job)
      subject.work
    end

    it 'should perform the job' do
      job.should_receive(:perform)
      subject.work
    end
  end

  describe 'work_off' do
    it 'should work all jobs off the queue' do
      Qu.should_receive(:pop).exactly(4).times.with(subject, :block => false).and_return(job, job, job, nil)
      subject.work_off
    end
  end

  describe 'stop' do
    before do
      job.stub(:perform) do
        Process.kill('SIGTERM', $$)
        sleep(0.01)
      end
      Qu.stub!(:pop).and_return(job)
    end

    context 'when stopping' do
      it 'should wait for the job to finish and shut down gracefully' do
        Qu.graceful_shutdown = true
        subject.start
      end

      it 'should stop if the worker is blocked waiting for a new job' do
        Qu.stub(:pop) { sleep }

        t = Thread.new do
          sleep(0.01)
          Process.kill('SIGTERM', $$)
        end

        expect { subject.start }.to raise_exception(Qu::Worker::Stop)
      end
    end
  end

  describe 'pid' do
    it 'should equal process id' do
      subject.pid.should == Process.pid
    end

    it 'should use provided pid' do
      Qu::Worker.new(:pid => 1).pid.should == 1
    end
  end

  describe 'id' do
    it 'should return hostname, pid, and queues' do
      worker = Qu::Worker.new('a', 'b', :hostname => 'quspec', :pid => 123)
      worker.id.should == 'quspec:123:a,b'
    end

    it 'should not expand star in queue names' do
      Qu::Worker.new('a', '*').id.should =~ /a,*/
    end
  end

  describe 'hostname' do
    it 'should get hostname' do
      subject.hostname.should_not be_empty
    end

    it 'should use provided hostname' do
      Qu::Worker.new(:hostname => 'quspec').hostname.should == 'quspec'
    end
  end

  describe 'attributes' do
    let(:attrs) do
      {'hostname' => 'omgbbq', 'pid' => 987, 'queues' => ['a', '*']}
    end

    it 'should return hash of attributes' do
      Qu::Worker.new(attrs).attributes.should == attrs
    end
  end
end
