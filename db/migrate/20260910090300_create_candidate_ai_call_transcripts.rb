# frozen_string_literal: true

# Kept separate from candidate_ai_calls (AGENTS.md: "avoid loading
# unnecessary columns") since a call transcript is a verbatim recording of a
# candidate discussing personal/case details -- often more sensitive than
# the header row every admin list/detail view loads. Write-once via
# Active Record Encryption (`transcript`, same in-place-encrypted-column
# pattern as Candidate#cnic / CandidateBankDetail#account_number), with an
# explicit, narrow purge path (`purged_at`) rather than a blanket
# ImmutableRecord -- that concern has no escape hatch, and a transcript
# containing CNIC/passport/medical/financial information cannot be
# architected as permanently undeletable.
class CreateCandidateAiCallTranscripts < ActiveRecord::Migration[8.1]
  def change
    create_table :candidate_ai_call_transcripts do |t|
      t.references :candidate_ai_call, null: false, foreign_key: true, index: { unique: true }
      t.text :transcript
      t.string :recording_reference
      t.datetime :recorded_at
      t.datetime :expires_at
      t.datetime :redacted_at
      t.datetime :purged_at

      t.timestamps
    end
  end
end
