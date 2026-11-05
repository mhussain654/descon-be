# frozen_string_literal: true

# Reaching Verified (and the fee stages after it) needs the candidate's bank
# details verified as well as their documents
# (CandidateWorkflows::PrerequisiteValidator#bank_detail_verified?).
module BankDetailHelpers
  def create_verified_bank_detail(assignment:)
    CandidateBankDetail.current_version.find_by(candidate_assignment: assignment, status_code: 'verified') ||
      create(:candidate_bank_detail, candidate_assignment: assignment, status_code: 'verified',
                                     reviewed_at: Time.current)
  end
end

RSpec.configure do |config|
  config.include BankDetailHelpers
end
