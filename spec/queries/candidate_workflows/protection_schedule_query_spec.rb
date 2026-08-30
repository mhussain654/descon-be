# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateWorkflows::ProtectionScheduleQuery do
  it 'returns protection records awaiting ready-to-fly completion in appeared date order' do
    ready_actor = create(:user)
    first = create(
      :candidate_protection_record,
      appeared_on: Date.new(2026, 9, 10),
      appeared_recorded_at: Time.zone.parse('2026-09-10T10:00:00Z'),
      appeared_recorded_by: ready_actor
    )
    second = create(
      :candidate_protection_record,
      appeared_on: Date.new(2026, 9, 12),
      appeared_recorded_at: Time.zone.parse('2026-09-12T10:00:00Z'),
      appeared_recorded_by: ready_actor
    )
    create(
      :candidate_protection_record,
      appeared_on: Date.new(2026, 9, 8),
      appeared_recorded_at: Time.zone.parse('2026-09-08T10:00:00Z'),
      appeared_recorded_by: ready_actor,
      protected_on: Date.new(2026, 9, 9),
      ready_to_fly_at: Time.zone.parse('2026-09-09T10:00:00Z'),
      ready_recorded_by: ready_actor
    )

    result = described_class.call

    expect(result).to eq([first, second])
  end
end
