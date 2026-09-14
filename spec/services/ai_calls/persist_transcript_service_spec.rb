# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::PersistTranscriptService do
  let(:call_record) { create(:candidate_ai_call, status: 'in_progress') }
  let(:payload) do
    instance_double(AiCalls::PostCallWebhookPayload, transcript_text: 'Hello.', recording_reference: 'ref-1')
  end

  it 'creates the transcript with an expiry stamped from the configured retention window' do
    freeze_time do
      described_class.call(call_record:, payload:)

      transcript = call_record.reload.candidate_ai_call_transcript
      expect(transcript.transcript).to eq('Hello.')
      expect(transcript.expires_at).to eq(90.days.from_now)
    end
  end

  it 'honors a custom retention window' do
    configuration = instance_double(AiCalls::Configuration, transcript_retention_days: 30)

    freeze_time do
      described_class.call(call_record:, payload:, configuration:)

      expect(call_record.reload.candidate_ai_call_transcript.expires_at).to eq(30.days.from_now)
    end
  end

  it 'is a no-op when the transcript text is blank' do
    blank_payload = instance_double(AiCalls::PostCallWebhookPayload, transcript_text: nil, recording_reference: nil)

    described_class.call(call_record:, payload: blank_payload)

    expect(call_record.reload.candidate_ai_call_transcript).to be_nil
  end

  it 'is a no-op when a transcript already exists' do
    create(:candidate_ai_call_transcript, candidate_ai_call: call_record, transcript: 'Existing.')

    described_class.call(call_record:, payload:)

    expect(call_record.reload.candidate_ai_call_transcript.transcript).to eq('Existing.')
  end
end
