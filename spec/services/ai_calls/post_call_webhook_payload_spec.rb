# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::PostCallWebhookPayload do
  subject(:payload) { described_class.new(raw) }

  let(:raw) do
    {
      'type' => 'post_call_transcription',
      'data' => {
        'conversation_id' => 'conversation-1',
        'metadata' => {
          'call_duration_secs' => 42,
          'phone_call' => { 'recording_url' => 'https://elevenlabs.example.test/recordings/1' }
        },
        'analysis' => {
          'data_collection_results' => {
            'human_answered' => true, 'call_resolved' => true, 'callback_requested' => false,
            'escalation_requested' => false
          }
        },
        'transcript' => [
          { 'role' => 'agent', 'message' => 'Hello, this is Descon Manpower.' },
          { 'role' => 'user', 'message' => 'Hi, yes I can hear you.' }
        ]
      }
    }
  end

  it 'reads the conversation id' do
    expect(payload.conversation_id).to eq('conversation-1')
  end

  it 'reads the call duration' do
    expect(payload.call_duration_seconds).to eq(42)
  end

  it 'reads the recording reference' do
    expect(payload.recording_reference).to eq('https://elevenlabs.example.test/recordings/1')
  end

  it 'reads the structured extraction' do
    expect(payload.extraction).to eq(
      'human_answered' => true, 'call_resolved' => true, 'callback_requested' => false,
      'escalation_requested' => false
    )
  end

  it 'joins the transcript turns into one text block' do
    expect(payload.transcript_text).to eq("Hello, this is Descon Manpower.\nHi, yes I can hear you.")
  end

  it 'handles a missing or malformed payload without raising' do
    empty = described_class.new(nil)

    expect(empty.conversation_id).to be_nil
    expect(empty.extraction).to be_nil
    expect(empty.transcript_text).to be_nil
    expect(empty.recording_reference).to be_nil
  end

  it 'accepts string-keyed hashes without a nested data wrapper' do
    flat = described_class.new('conversation_id' => 'conversation-2')

    expect(flat.conversation_id).to eq('conversation-2')
  end
end
