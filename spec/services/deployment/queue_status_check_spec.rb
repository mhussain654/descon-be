# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Deployment::QueueStatusCheck do
  def create_process(kind:, heartbeat_at: Time.current)
    SolidQueue::Process.create!(kind:, last_heartbeat_at: heartbeat_at, pid: rand(10_000..60_000),
                                hostname: 'test-host', name: "#{kind}-#{SecureRandom.hex(4)}")
  end

  describe '.call' do
    context 'when a worker and a dispatcher are heartbeating' do
      it 'passes and lists the live processes' do
        create_process(kind: 'Worker')
        create_process(kind: 'Dispatcher')
        create_process(kind: 'Scheduler')

        result = described_class.call

        expect(result.status).to eq(:pass)
        expect(result.detail).to include('Dispatcher x1', 'Scheduler x1', 'Worker x1')
      end
    end

    context 'when there are no live processes' do
      it 'fails and says so' do
        result = described_class.call

        expect(result).to be_failed
        expect(result.detail).to include('no live Solid Queue processes', 'missing Worker, Dispatcher')
      end
    end

    context 'when the only worker stopped heartbeating' do
      it 'fails because a stale row does not prove jobs are running' do
        create_process(kind: 'Worker', heartbeat_at: 10.minutes.ago)
        create_process(kind: 'Dispatcher')

        result = described_class.call

        expect(result).to be_failed
        expect(result.detail).to include('missing Worker')
      end
    end
  end
end
