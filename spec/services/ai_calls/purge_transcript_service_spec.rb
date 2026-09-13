# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::PurgeTranscriptService do
  let(:candidate_ai_call) { create(:candidate_ai_call, elevenlabs_conversation_id: 'conversation-1') }
  let(:transcript) do
    create(:candidate_ai_call_transcript, candidate_ai_call:, transcript: 'Agent: Hello.',
                                          recording_reference: 'rec-123')
  end

  it 'clears the content and stamps purged_at' do
    result = described_class.call(candidate_ai_call_transcript: transcript)

    expect(result).to have_attributes(transcript: nil, recording_reference: nil, purged_at: be_present)
  end

  it 'records an immutable audit event on the parent call' do
    described_class.call(candidate_ai_call_transcript: transcript)

    event = candidate_ai_call.candidate_ai_call_events.find_by(event_type: 'transcript_purged')
    expect(event).to have_attributes(provider_code: 'system', event_source: 'retention_purge')
    expect(event.payload).to eq('candidate_ai_call_transcript_id' => transcript.id)
  end

  it 'is a no-op when the transcript is already purged' do
    described_class.call(candidate_ai_call_transcript: transcript)
    already_purged = transcript.reload

    expect { described_class.call(candidate_ai_call_transcript: already_purged) }
      .not_to(change { candidate_ai_call.candidate_ai_call_events.count })
  end

  it 'does not double-purge under a concurrent duplicate event' do
    candidate_ai_call.candidate_ai_call_events.create!(
      provider_code: 'system', event_source: 'retention_purge', event_type: 'transcript_purged',
      event_key: "retention:#{candidate_ai_call.id}:transcript_purged", occurred_at: Time.current, payload: {}
    )

    result = described_class.call(candidate_ai_call_transcript: transcript)

    expect(result.transcript).to eq('Agent: Hello.')
    expect(result.purged_at).to be_nil
  end
end
