# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::OutcomeTrackingQuery do
  it 'counts rejected documents, QVC outcomes and visa rejections for current assignments only' do
    assignment = create(:candidate_assignment)
    other_assignment = create(:candidate_assignment)
    reviewer = create(:user)
    create(:candidate_document, candidate_assignment: assignment, status_code: 'rejected', verified_by: reviewer,
                                verified_at: Time.current, rejection_reason: 'Illegible scan')
    create(:candidate_document, candidate_assignment: assignment, status_code: 'verified', verified_by: reviewer,
                                verified_at: Time.current)
    create(:candidate_document, candidate_assignment: assignment, status_code: 'rejected', verified_by: reviewer,
                                verified_at: Time.current, rejection_reason: 'Illegible scan', superseded_at: 1.day.ago)
    create(:candidate_qvc_attempt, candidate_assignment: assignment, outcome_code: 're_medical',
                                   outcome_recorded_at: Time.current, outcome_recorded_by: reviewer)
    create(:candidate_qvc_attempt, candidate_assignment: assignment, outcome_code: 'rejected',
                                   outcome_recorded_at: Time.current, outcome_recorded_by: reviewer)
    create(:candidate_qvc_attempt, candidate_assignment: assignment, no_show: true,
                                   outcome_recorded_at: Time.current, outcome_recorded_by: reviewer)
    create(:candidate_visa_decision, :rejected, candidate_assignment: assignment)
    create(:candidate_visa_decision, candidate_assignment: assignment, outcome_code: 'issued')
    create(:candidate_document, candidate_assignment: other_assignment, status_code: 'rejected', verified_by: reviewer,
                                verified_at: Time.current, rejection_reason: 'Illegible scan')

    # other_assignment is not any candidate's *current* assignment, so it must not contribute counts
    create(:candidate_assignment, candidate: other_assignment.candidate)

    result = described_class.call

    expect(result).to eq(
      rejected_documents: 1,
      qvc_re_medical: 1,
      qvc_rejected: 1,
      qvc_no_show: 1,
      visa_rejected: 1
    )
  end

  it 'zero-fills when there is nothing to report' do
    create(:candidate_assignment)

    expect(described_class.call).to eq(
      rejected_documents: 0,
      qvc_re_medical: 0,
      qvc_rejected: 0,
      qvc_no_show: 0,
      visa_rejected: 0
    )
  end
end
