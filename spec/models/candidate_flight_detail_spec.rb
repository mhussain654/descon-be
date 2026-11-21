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

  it 'requires airline and flight number, the route (sector) being optional' do
    detail = build(:candidate_flight_detail, airline: nil, flight_number: nil, sector: nil)

    expect(detail).not_to be_valid
    expect(detail.errors[:airline]).to include("can't be blank")
    expect(detail.errors[:flight_number]).to include("can't be blank")
    expect(detail.errors[:sector]).to be_empty
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

  describe 'mobilization date' do
    it 'cannot be later than today in Pakistan' do
      detail = create(:candidate_flight_detail, flight_departure_at: 3.days.ago)
      history = create(:candidate_stage_history, candidate_assignment: detail.candidate_assignment,
                                                 to_workflow_stage: WorkflowStage.find_by!(code: 'mobilized'))

      detail.assign_attributes(mobilized_on: described_class.pakistan_today + 1, mobilized_stage_history: history,
                               mobilized_recorded_by: create(:user))
      expect(detail).not_to be_valid
      expect(detail.errors[:mobilized_on]).to be_present

      detail.mobilized_on = described_class.pakistan_today
      expect(detail).to be_valid
    end
  end

  describe '#departure_status' do
    let(:today) { Date.new(2026, 11, 21) }

    # 12:00 on the given day in Pakistan.
    def flight_on(day, **attributes)
      build(:candidate_flight_detail, flight_departure_at: Time.utc(day.year, day.month, day.day, 7, 0), **attributes)
    end

    it 'is scheduled before the flight day and departing today on it' do
      expect(flight_on(today + 1).departure_status(today)).to eq('scheduled')
      expect(flight_on(today, boarding_pass_uploaded_at: Time.current).departure_status(today)).to eq('departing_today')
    end

    it 'is departed once staff record the mobilization, or once the flight day has passed with a boarding pass' do
      expect(flight_on(today, mobilized_on: today).departure_status(today)).to eq('departed')
      expect(flight_on(today - 1, boarding_pass_uploaded_at: Time.current).departure_status(today)).to eq('departed')
    end

    it 'is not confirmed once the flight day has passed with neither' do
      expect(flight_on(today - 1).departure_status(today)).to eq('not_confirmed')
    end

    it 'only counts a boarding pass OCR matched (or could not check) that staff did not reject' do
      uploaded = { boarding_pass_uploaded_at: Time.current }
      { 'matched' => 'departed', 'unavailable' => 'departed', nil => 'departed',
        'needs_review' => 'not_confirmed', 'not_boarding_pass' => 'not_confirmed', 'pending' => 'not_confirmed' }
        .each do |check, status|
          flight = flight_on(today - 1, **uploaded, boarding_pass_check: check)
          expect(flight.departure_status(today)).to eq(status), check.inspect
        end
      rejected = flight_on(today - 1, **uploaded, boarding_pass_check: 'matched',
                                                  boarding_pass_rejected_at: Time.current)
      expect(rejected.departure_status(today)).to eq('not_confirmed')
    end

    it 'ignores a mobilization date that is still ahead (recorded before that was refused)' do
      expect(flight_on(today + 3, mobilized_on: today + 6).departure_status(today)).to eq('scheduled')
    end
  end

  describe '#boarding_pass_upload_closes_on' do
    let(:detail) { build(:candidate_flight_detail, flight_departure_at: Time.utc(2026, 11, 20, 7, 0)) }

    it 'is 2 days after the flight day, or 2 days after a later rejection' do
      expect(detail.boarding_pass_upload_closes_on).to eq(Date.new(2026, 11, 22))

      detail.boarding_pass_rejected_at = Time.utc(2026, 11, 18, 7, 0)
      expect(detail.boarding_pass_upload_closes_on).to eq(Date.new(2026, 11, 22))

      detail.boarding_pass_rejected_at = Time.utc(2026, 11, 25, 20, 0) # 26 Nov in Pakistan
      expect(detail.boarding_pass_upload_closes_on).to eq(Date.new(2026, 11, 28))
    end
  end
end
