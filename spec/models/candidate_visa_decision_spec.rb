# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateVisaDecision, type: :model do
  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:candidate_stage_history) }
  it { is_expected.to belong_to(:recorded_by).class_name('User') }

  it 'assigns a public id on create' do
    decision = create(:candidate_visa_decision)

    expect(decision.public_id).to be_present
  end

  it 'is invalid when outcome_code is not issued or rejected' do
    decision = build(:candidate_visa_decision, outcome_code: 'pending')

    expect(decision).not_to be_valid
    expect(decision.errors[:outcome_code]).to include('is not included in the list')
  end

  it 'rejects an issued outcome that carries a rejection reason' do
    decision = build(:candidate_visa_decision, outcome_code: 'issued', rejection_reason_code: 'other')

    expect(decision).not_to be_valid
    expect(decision.errors[:rejection_reason_code]).to include('must be blank')
  end

  it 'requires a structured rejection reason for a rejected outcome' do
    decision = build(:candidate_visa_decision, outcome_code: 'rejected', rejection_reason_code: nil)

    expect(decision).not_to be_valid
    expect(decision.errors[:rejection_reason_code]).to include("can't be blank")
  end

  it 'rejects an unsupported rejection reason code' do
    decision = build(:candidate_visa_decision, :rejected, rejection_reason_code: 'not_a_real_reason')

    expect(decision).not_to be_valid
    expect(decision.errors[:rejection_reason_code]).to include('is not included in the list')
  end

  it 'is valid with a supported issued outcome' do
    expect(build(:candidate_visa_decision)).to be_valid
  end

  it 'is valid with a supported rejected outcome and reason' do
    expect(build(:candidate_visa_decision, :rejected)).to be_valid
  end
end
