# frozen_string_literal: true

# Backfills any transcript row left with a nil `expires_at` (previously
# possible via AiCalls::ReconcileCallService's own copy of the persistence
# method, which never stamped one -- see AiCalls::PersistTranscriptService,
# now the only writer), then enforces the invariant at the database level
# so a future writer can't silently reintroduce the same gap.
class EnforceCandidateAiCallTranscriptExpiry < ActiveRecord::Migration[8.1]
  def up
    default_retention_days = ENV.fetch('AI_VOICE_TRANSCRIPT_RETENTION_DAYS', 90).to_i
    execute <<~SQL.squish
      UPDATE candidate_ai_call_transcripts
      SET expires_at = COALESCE(recorded_at, created_at) + INTERVAL '#{default_retention_days} days'
      WHERE expires_at IS NULL
    SQL

    change_column_null :candidate_ai_call_transcripts, :expires_at, false
  end

  def down
    change_column_null :candidate_ai_call_transcripts, :expires_at, true
  end
end
