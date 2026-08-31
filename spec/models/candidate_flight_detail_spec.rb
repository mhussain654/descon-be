# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateFlightDetail, type: :model do
  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:candidate_stage_history) }
  it { is_expected.to belong_to(:mobilized_stage_history).class_name('CandidateStageHistory').optional }
  it { is_expected.to belong_to(:recorded_by).class_name('User') }
  it { is_expected.to belong_to(:mobilized_recorded_by).class_name('User').optional }

  it 'assigns a public id on create' do
    detail = create(:candidate_flight_detail)

    expect(detail.public_id).to be_present
  end

  it 'requires airline, flight number and sector' do
    detail = build(:candidate_flight_detail, airline: nil, flight_number: nil, sector: nil)

    expect(detail).not_to be_valid
    expect(detail.errors[:airline]).to include("can't be blank")
    expect(detail.errors[:flight_number]).to include("can't be blank")
    expect(detail.errors[:sector]).to include("can't be blank")
  end

  it 'requires a recorded actor and stage history when mobilized_on is present' do
    detail = build(:candidate_flight_detail, mobilized_on: Date.current, mobilized_stage_history: nil,
                                             mobilized_recorded_by: nil)

    expect(detail).not_to be_valid
    expect(detail.errors[:mobilized_stage_history]).to include("can't be blank")
    expect(detail.errors[:mobilized_recorded_by]).to include("can't be blank")
  end

  it 'rejects a mobilization date before the flight departure date' do
    detail = build(:candidate_flight_detail, :mobilized, flight_departure_at: Time.zone.parse('2026-09-20T14:30:00Z'))
    detail.mobilized_on = Date.new(2026, 9, 19)

    expect(detail).not_to be_valid
    expect(detail.errors[:mobilized_on]).to include('is invalid')
  end

  it 'accepts a mobilization date on the same day as the flight departure' do
    detail = build(:candidate_flight_detail, :mobilized, flight_departure_at: Time.zone.parse('2026-09-20T14:30:00Z'))
    detail.mobilized_on = Date.new(2026, 9, 20)

    expect(detail).to be_valid
  end

  it 'becomes view-only for its core fields once mobilized' do
    detail = create(:candidate_flight_detail, :mobilized)

    detail.flight_number = 'QR-999'

    expect(detail).not_to be_valid
    expect(detail.errors[:base]).to include('is invalid')
  end

  it 'still allows unrelated saves once mobilized as long as core fields are untouched' do
    detail = create(:candidate_flight_detail, :mobilized)

    expect(detail).to be_valid
  end
end
