# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateQvcAttempt, type: :model do
  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:scheduled_by).class_name('User') }
  it { is_expected.to belong_to(:outcome_recorded_by).class_name('User').optional }

  it 'normalizes legacy re_medical_required to re_medical' do
    attempt = build(:candidate_qvc_attempt, outcome_code: 'RE_MEDICAL_REQUIRED')

    attempt.validate

    expect(attempt.outcome_code).to eq('re_medical')
  end

  it 'requires completed attempts to record the actor and timestamp' do
    attempt = build(:candidate_qvc_attempt, outcome_code: 'approved', outcome_recorded_at: nil, outcome_recorded_by: nil)

    expect(attempt).not_to be_valid
    expect(attempt.errors[:outcome_recorded_at]).to include("can't be blank")
    expect(attempt.errors[:outcome_recorded_by]).to include("can't be blank")
  end

  it 'does not allow outcome codes on no-show attempts' do
    attempt = build(
      :candidate_qvc_attempt,
      outcome_code: 'approved',
      no_show: true,
      outcome_recorded_at: Time.current,
      outcome_recorded_by: build(:user)
    )

    expect(attempt).not_to be_valid
    expect(attempt.errors[:outcome_code]).to include('is invalid')
  end
end
