# frozen_string_literal: true

# Staff can now verify or reject a candidate's bank details like their
# documents: a rejection keeps its reason so the candidate knows what to fix.
# The status check constraint, which allowed only "submitted", now also allows
# the two decisions (CandidateBankDetail::STATUS_CODES).
class AddReviewToCandidateBankDetails < ActiveRecord::Migration[8.1]
  def change
    add_column :candidate_bank_details, :rejection_reason, :text
    remove_check_constraint :candidate_bank_details, "status_code = 'submitted'",
                            name: 'candidate_bank_details_status_code'
    add_check_constraint :candidate_bank_details, "status_code IN ('submitted', 'verified', 'rejected')",
                         name: 'candidate_bank_details_status_code'
  end
end
