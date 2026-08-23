# frozen_string_literal: true

class CreateCandidateOtpChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :candidate_otp_challenges do |t|
      t.references :candidate, null: false, foreign_key: true
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.integer :attempts, null: false, default: 0
      # Audit-only correlation with the request's source IP (AGENTS.md:
      # "Record security-sensitive and administrative actions in an audit
      # trail") -- never used for identity/authorization decisions.
      t.string :requested_ip

      t.timestamps
    end

    # Finds "the most recent challenge for this candidate" (resend-cooldown
    # checks, verify lookups) without a table scan.
    add_index :candidate_otp_challenges, %i[candidate_id created_at]
    add_check_constraint :candidate_otp_challenges, 'attempts >= 0', name: 'candidate_otp_challenges_attempts_range'
  end
end
