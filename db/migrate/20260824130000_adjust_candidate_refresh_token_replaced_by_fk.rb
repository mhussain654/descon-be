# frozen_string_literal: true

class AdjustCandidateRefreshTokenReplacedByFk < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :candidate_refresh_tokens, column: :replaced_by_id
    add_foreign_key :candidate_refresh_tokens,
                    :candidate_refresh_tokens,
                    column: :replaced_by_id,
                    on_delete: :nullify
  end

  def down
    remove_foreign_key :candidate_refresh_tokens, column: :replaced_by_id
    add_foreign_key :candidate_refresh_tokens, :candidate_refresh_tokens, column: :replaced_by_id
  end
end
