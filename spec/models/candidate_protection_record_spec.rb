# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateProtectionRecord, type: :model do
  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:appeared_recorded_by).class_name('User').optional }
  it { is_expected.to belong_to(:ready_recorded_by).class_name('User').optional }

  it 'requires a recorded appearance before ready-to-fly details can be stored' do
    record = build(
      :candidate_protection_record,
      protected_on: Date.current,
      ready_to_fly_at: Time.current,
      ready_recorded_by: build(:user)
    )

    expect(record).not_to be_valid
    expect(record.errors[:protected_on]).to include('is invalid')
  end

  it 'requires a recorded actor and timestamp when an appearance is stored' do
    record = build(:candidate_protection_record, appeared_on: Date.current, appeared_recorded_at: nil)

    expect(record).not_to be_valid
    expect(record.errors[:appeared_recorded_at]).to include("can't be blank")
    expect(record.errors[:appeared_recorded_by]).to include("can't be blank")
  end
end
