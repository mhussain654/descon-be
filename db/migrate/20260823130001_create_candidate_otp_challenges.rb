# frozen_string_literal: true

class CreateCandidateOtpChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :candidate_otp_challenges do |t|
      # Nullable: a row with no candidate is a decoy, created for a CNIC that
      # does not resolve to a real candidate, so /verify has a real challenge
      # to evaluate against either way and otp_expired/otp_max_attempts
      # cannot be used to distinguish a real CNIC from an unknown one.
      t.references :candidate, null: true, foreign_key: true
      # Populated for both real and decoy challenges and used as the lookup
      # key instead of the candidate association, which decoys don't have.
      t.string :cnic, null: false
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

    # Finds "the most recent challenge for this CNIC" (resend-cooldown
    # checks, verify lookups) without a table scan.
    add_index :candidate_otp_challenges, %i[cnic created_at]
    add_check_constraint :candidate_otp_challenges, 'attempts >= 0', name: 'candidate_otp_challenges_attempts_range'
  end
end
