# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateAiCallTranscript, type: :model do
  subject(:transcript) { build(:candidate_ai_call_transcript) }

  it { is_expected.to belong_to(:candidate_ai_call) }

  it 'encrypts the transcript column at rest' do
    transcript.transcript = 'Agent: Hello. Candidate: Hi.'
    transcript.save!

    raw_value = ActiveRecord::Base.connection.select_value(
      "SELECT transcript FROM candidate_ai_call_transcripts WHERE id = #{transcript.id}"
    )

    expect(raw_value).not_to include('Hello')
    expect(transcript.reload.transcript).to eq('Agent: Hello. Candidate: Hi.')
  end

  it 'cannot be destroyed' do
    persisted = create(:candidate_ai_call_transcript)

    expect { persisted.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'blocks updating any field outside the purge/redaction set' do
    persisted = create(:candidate_ai_call_transcript)

    expect { persisted.update!(recorded_at: Time.current) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'blocks setting transcript content for the first time via update (only #create! may set it)' do
    persisted = create(:candidate_ai_call_transcript, transcript: nil)

    expect { persisted.update!(transcript: 'new content') }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'blocks replacing existing transcript content with different content' do
    persisted = create(:candidate_ai_call_transcript, transcript: 'original')

    expect { persisted.update!(transcript: 'replaced') }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'allows purging (clearing) transcript and recording_reference alongside purged_at' do
    persisted = create(:candidate_ai_call_transcript, transcript: 'original', recording_reference: 'rec-123')

    persisted.update!(transcript: nil, recording_reference: nil, purged_at: Time.current)

    expect(persisted.reload).to have_attributes(transcript: nil, recording_reference: nil, purged_at: be_present)
  end

  it 'allows stamping redacted_at on its own' do
    persisted = create(:candidate_ai_call_transcript)

    expect { persisted.update!(redacted_at: Time.current) }.not_to raise_error
  end
end
