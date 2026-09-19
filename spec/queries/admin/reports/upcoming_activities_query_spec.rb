# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::UpcomingActivitiesQuery do
  let(:reference_time) { Time.zone.parse('2026-09-18 09:00:00') }

  it 'includes a QVC appointment within the next 7 days' do
    assignment = create(:candidate_assignment)
    create(:candidate_qvc_attempt, candidate_assignment: assignment, appointment_date: reference_time.to_date + 3.days)

    result = described_class.call(reference_time:)

    expect(result).to contain_exactly(
      hash_including(type: 'qvc_appointment', candidate_assignment_public_id: assignment.public_id)
    )
  end

  it 'excludes a QVC appointment beyond the 7-day window' do
    assignment = create(:candidate_assignment)
    create(:candidate_qvc_attempt, candidate_assignment: assignment, appointment_date: reference_time.to_date + 8.days)

    expect(described_class.call(reference_time:)).to be_empty
  end

  it 'excludes a QVC attempt that already has a recorded outcome' do
    assignment = create(:candidate_assignment)
    create(:candidate_qvc_attempt, candidate_assignment: assignment, appointment_date: reference_time.to_date + 1.day,
                                   outcome_code: 'approved', outcome_recorded_at: reference_time,
                                   outcome_recorded_by: create(:user))

    expect(described_class.call(reference_time:)).to be_empty
  end

  it 'includes a flight departure within the next 7 days' do
    assignment = create(:candidate_assignment)
    create(:candidate_flight_detail, candidate_assignment: assignment, flight_departure_at: reference_time + 4.days)

    result = described_class.call(reference_time:)

    expect(result).to contain_exactly(
      hash_including(type: 'flight_departure', candidate_assignment_public_id: assignment.public_id)
    )
  end

  it 'excludes a flight departure beyond the 7-day window' do
    assignment = create(:candidate_assignment)
    create(:candidate_flight_detail, candidate_assignment: assignment, flight_departure_at: reference_time + 10.days)

    expect(described_class.call(reference_time:)).to be_empty
  end

  it 'merges and sorts QVC appointments and flight departures by date' do
    later_assignment = create(:candidate_assignment)
    create(:candidate_qvc_attempt, candidate_assignment: later_assignment,
                                   appointment_date: reference_time.to_date + 5.days)
    earlier_assignment = create(:candidate_assignment)
    create(:candidate_flight_detail, candidate_assignment: earlier_assignment,
                                     flight_departure_at: reference_time + 1.day)

    result = described_class.call(reference_time:)

    expect(result.map { |row| row.fetch(:candidate_assignment_public_id) }).to eq(
      [earlier_assignment.public_id, later_assignment.public_id]
    )
  end
end
