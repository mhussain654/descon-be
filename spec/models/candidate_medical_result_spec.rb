# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateMedicalResult, type: :model do
  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:candidate_stage_history).optional }
  it { is_expected.to belong_to(:recorded_by).class_name('User') }

  it 'accepts only fit or unfit with a result date, and assigns a public id' do
    result = create(:candidate_medical_result)

    expect(result.public_id).to match(/\A[0-9a-f-]{36}\z/)
    expect(result).to be_fit
    expect(build(:candidate_medical_result, outcome_code: 'pending')).not_to be_valid
    expect(build(:candidate_medical_result, result_date: nil)).not_to be_valid
  end

  it 'orders the newest result first' do
    assignment = create(:candidate_assignment)
    older = create(:candidate_medical_result, candidate_assignment: assignment, outcome_code: 'unfit')
    newer = create(:candidate_medical_result, candidate_assignment: assignment, outcome_code: 'fit')

    expect(assignment.candidate_medical_results.latest_first).to eq([newer, older])
  end
end
