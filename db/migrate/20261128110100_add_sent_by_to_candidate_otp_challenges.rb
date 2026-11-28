# frozen_string_literal: true

# The staff member (a developer) who sent a sign-in code from the candidate
# page; null for a code the candidate requested in the app. A nullable column
# does not rewrite the table, and the table only holds short-lived codes.
class AddSentByToCandidateOtpChallenges < ActiveRecord::Migration[8.1]
  def change
    add_reference :candidate_otp_challenges, :sent_by, null: true, index: true, foreign_key: { to_table: :users }
  end
end
