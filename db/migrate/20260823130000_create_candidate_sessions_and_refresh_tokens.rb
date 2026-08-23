# frozen_string_literal: true

# Parallel to sessions/refresh_tokens (staff), not a polymorphic extension of
# them -- candidates authenticate via CNIC+OTP (not password), have a
# materially different, more restricted API surface, and keeping the token
# machinery structurally separate means a candidate token can never be
# confused with or grant staff-level access, even if the two ever shared a
# signing secret. Mirrors the exact same shape/conventions (digest-at-rest,
# rotation, reuse detection) as the existing sessions/refresh_tokens tables.
class CreateCandidateSessionsAndRefreshTokens < ActiveRecord::Migration[8.1]
  def change
    create_candidate_sessions
    create_candidate_refresh_tokens
  end

  private

  def create_candidate_sessions
    create_table :candidate_sessions do |t|
      t.references :candidate, null: false, foreign_key: true
      t.string :public_id, null: false
      t.string :jti, null: false
      t.string :user_agent
      t.string :ip_address
      t.datetime :revoked_at
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :candidate_sessions, :public_id, unique: true
    add_index :candidate_sessions, :jti, unique: true
    add_index :candidate_sessions, %i[candidate_id revoked_at]
  end

  def create_candidate_refresh_tokens
    create_table :candidate_refresh_tokens do |t|
      t.references :candidate_session, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.datetime :rotated_at
      t.bigint :replaced_by_id

      t.timestamps
    end

    add_index :candidate_refresh_tokens, :token_digest, unique: true
    add_index :candidate_refresh_tokens, :expires_at
    add_index :candidate_refresh_tokens, :replaced_by_id
  end
end
