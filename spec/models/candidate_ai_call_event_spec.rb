# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateAiCallEvent, type: :model do
  subject(:event) { build(:candidate_ai_call_event) }

  it { is_expected.to belong_to(:candidate_ai_call) }
  it { is_expected.to belong_to(:actor).class_name('User').optional }

  it 'is immutable after creation' do
    persisted_event = create(:candidate_ai_call_event)

    expect { persisted_event.update!(event_type: 'changed') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { persisted_event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'normalizes provider/source/type codes' do
    event.provider_code = ' ElevenLabs '
    event.event_source = ' WEBHOOK '
    event.event_type = ' Post_Call_Transcription '

    event.validate

    expect(event.provider_code).to eq('elevenlabs')
    expect(event.event_source).to eq('webhook')
    expect(event.event_type).to eq('post_call_transcription')
  end

  it 'requires payload to be present' do
    event.payload = nil

    expect(event).not_to be_valid
    expect(event.errors[:payload]).to be_present
  end

  it 'rejects a duplicate (provider_code, event_key) pair -- the webhook-idempotency guarantee' do
    create(:candidate_ai_call_event, provider_code: 'elevenlabs', event_key: 'shared-key')

    duplicate = build(:candidate_ai_call_event, provider_code: 'elevenlabs', event_key: 'shared-key')

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
