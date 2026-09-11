# frozen_string_literal: true

# Raw (unmasked) caller-ID number captured at inbound conversation-initiation
# time, used only for the server-side "is this the candidate's own
# registered number" verification comparison (see AiCalls::
# VerifyCallerIdentityService). Deliberately separate from the existing
# `caller_number_masked` column, which is the only form ever serialized,
# logged, or otherwise exposed -- this raw column must never be.
class AddCallerNumberToCandidateAiCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :candidate_ai_calls, :caller_number, :string
  end
end
