# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::PurgeExpiredTranscriptsJob do
  def transcript_for(expires_at:, purged_at: nil)
    call = create(:candidate_ai_call, elevenlabs_conversation_id: SecureRandom.uuid)
    create(:candidate_ai_call_transcript, candidate_ai_call: call, expires_at:, purged_at:,
                                          transcript: purged_at ? nil : 'Agent: Hello.')
  end

  it 'purges a transcript past its retention window' do
    expired = transcript_for(expires_at: 1.day.ago)

    described_class.perform_now

    expect(expired.reload).to have_attributes(transcript: nil, purged_at: be_present)
  end

  it 'leaves a transcript still within its retention window untouched' do
    fresh = transcript_for(expires_at: 1.day.from_now)

    described_class.perform_now

    expect(fresh.reload).to have_attributes(transcript: 'Agent: Hello.', purged_at: nil)
  end

  it 'does not reprocess an already-purged transcript' do
    already_purged = transcript_for(expires_at: 1.day.ago, purged_at: 2.days.ago)

    expect { described_class.perform_now }
      .not_to(change { CandidateAiCallEvent.where(candidate_ai_call: already_purged.candidate_ai_call).count })
  end

  it 'is idempotent across repeated runs' do
    transcript_for(expires_at: 1.day.ago)

    described_class.perform_now

    expect { described_class.perform_now }.not_to change(CandidateAiCallEvent, :count)
  end
end
