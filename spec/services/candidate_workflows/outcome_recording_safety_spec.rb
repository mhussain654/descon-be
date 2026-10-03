# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Candidate workflow outcome recording safety' do
  let(:actor) { create(:user, role: 'mps') }

  before { ensure_staff_authorization_reference_data! }

  def candidate_at(stage_code)
    candidate = create(:candidate, status_code: stage_code)
    create(:candidate_assignment, candidate:, country: process_country(:qatar),
                                  current_workflow_stage: WorkflowStage.find_by!(code: stage_code))
    candidate
  end

  def record_medical(candidate)
    CandidateWorkflows::MedicalResults::RecordService.call(
      actor:, candidate:, outcome_code: 'fit', result_date: '2026-09-05',
      expected_current_stage_code: 'medical_fit', request_id: SecureRandom.uuid
    )
  end

  def record_visa(candidate)
    CandidateWorkflows::VisaDecisions::RecordService.call(
      actor:, candidate:, outcome_code: 'rejected', decision_date: '2026-09-05',
      rejection_reason_code: 'embassy_rejection', expected_current_stage_code: 'visa_issued_or_rejected',
      request_id: SecureRandom.uuid
    )
  end

  it 'refuses a medical re-decision when a previously loaded candidate has been deactivated' do
    candidate = candidate_at('medical_fit')
    Candidate.find(candidate.id).update!(active: false)

    expect { record_medical(candidate) }.to raise_error(InactiveAccountError)
    expect(candidate.current_assignment.candidate_medical_results).to be_empty
  end

  it 'requires a nonblank expected stage before recording a medical result' do
    candidate = candidate_at('medical_fit')

    [nil, '', ' '].each do |expected_current_stage_code|
      expect do
        CandidateWorkflows::MedicalResults::RecordService.call(
          actor:, candidate:, outcome_code: 'fit', result_date: '2026-09-05',
          expected_current_stage_code:, request_id: SecureRandom.uuid
        )
      end.to raise_error(ValidationError)
    end
    expect(candidate.current_assignment.candidate_medical_results).to be_empty
  end

  it 'refuses a visa re-decision when a previously loaded candidate has been deactivated' do
    candidate = candidate_at('visa_issued_or_rejected')
    Candidate.find(candidate.id).update!(active: false)

    expect { record_visa(candidate) }.to raise_error(InactiveAccountError)
    expect(candidate.current_assignment.candidate_visa_decisions).to be_empty
  end

  it 'does not re-decide medical results on a cached assignment after a new assignment starts' do
    candidate = candidate_at('medical_fit')
    candidate.candidate_assignments.load
    create(:candidate_assignment, candidate:, country: process_country(:qatar))

    expect { record_medical(candidate) }.to raise_error(InvalidWorkflowTransitionError)
    expect(CandidateMedicalResult.where(candidate_assignment: candidate.candidate_assignments)).to be_empty
  end

  it 'does not re-decide visas on a cached assignment after a new assignment starts' do
    candidate = candidate_at('visa_issued_or_rejected')
    candidate.candidate_assignments.load
    create(:candidate_assignment, candidate:, country: process_country(:qatar))

    expect { record_visa(candidate) }.to raise_error(WorkflowTransitionStaleError)
    expect(CandidateVisaDecision.where(candidate_assignment: candidate.candidate_assignments)).to be_empty
  end
end
