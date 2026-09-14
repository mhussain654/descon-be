# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::WebhookEventRecorder do
  let(:candidate_ai_call) { create(:candidate_ai_call, status: 'queued') }

  def event(event_key: 'elevenlabs:conversation-1:post_call_transcription')
    { provider_code: 'elevenlabs', event_source: 'webhook', event_type: 'post_call_transcription',
      event_key:, occurred_at: Time.current, payload: { outcome: 'answered' }, request_id: 'req-1' }
  end

  it 'runs the block and records the event on a new delivery' do
    recorder = described_class.new(candidate_ai_call:, event: event)
    block_ran = false

    result = recorder.call { |record| block_ran = record.update!(status: 'completed') }

    expect(block_ran).to be(true)
    expect(result.replayed).to be(false)
    expect(result.candidate_ai_call.status).to eq('completed')
    expect(candidate_ai_call.candidate_ai_call_events.sole.event_type).to eq('post_call_transcription')
  end

  it 'skips the block and reports replayed: true on a duplicate event_key' do
    described_class.new(candidate_ai_call:, event: event).call { |record| record.update!(status: 'completed') }

    block_ran = false
    result = described_class.new(candidate_ai_call:, event: event).call { |_record| block_ran = true }

    expect(block_ran).to be(false)
    expect(result.replayed).to be(true)
    expect(candidate_ai_call.candidate_ai_call_events.count).to eq(1)
  end

  it 'does not record a second event for a different event_key' do
    described_class.new(candidate_ai_call:, event: event).call { |record| record.update!(status: 'completed') }
    described_class.new(candidate_ai_call:, event: event(event_key: 'elevenlabs:conversation-1:other')).call

    expect(candidate_ai_call.candidate_ai_call_events.count).to eq(2)
  end

  it 'works without a block' do
    result = described_class.new(candidate_ai_call:, event: event).call

    expect(result.replayed).to be(false)
    expect(candidate_ai_call.candidate_ai_call_events.count).to eq(1)
  end
end
