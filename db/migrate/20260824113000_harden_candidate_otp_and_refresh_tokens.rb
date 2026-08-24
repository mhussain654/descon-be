# frozen_string_literal: true

class HardenCandidateOtpAndRefreshTokens < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :candidate_refresh_tokens, :candidate_refresh_tokens, column: :replaced_by_id
  end
end
