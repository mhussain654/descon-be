# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::KpiTrendQuery do
  let(:reference_date) { Date.new(2026, 9, 18) }

  it 'returns a 14-day daily series for each metric, zero-filled on days with no activity' do
    result = described_class.call(reference_date:)

    expect(result.keys).to contain_exactly(:active_candidates, :paid_payments, :mobilized)
    expect(result.fetch(:active_candidates).size).to eq(14)
    expect(result.fetch(:active_candidates).first.fetch(:date)).to eq((reference_date - 13.days).iso8601)
    expect(result.fetch(:active_candidates).last.fetch(:date)).to eq(reference_date.iso8601)
    expect(result.fetch(:active_candidates)).to all(include(count: 0))
  end

  it 'counts candidates by their created_at date for active_candidates' do
    create(:candidate, created_at: reference_date.in_time_zone + 2.hours)
    create(:candidate, created_at: reference_date.in_time_zone + 5.hours)
    create(:candidate, created_at: (reference_date - 1.day).in_time_zone)

    result = described_class.call(reference_date:)
    by_date = result.fetch(:active_candidates).index_by { |row| row.fetch(:date) }

    expect(by_date.fetch(reference_date.iso8601).fetch(:count)).to eq(2)
    expect(by_date.fetch((reference_date - 1.day).iso8601).fetch(:count)).to eq(1)
  end

  it 'counts paid payments by their paid_at date' do
    assignment = create(:candidate_assignment)
    create(:payment, candidate_assignment: assignment, status_code: 'paid', paid_at: reference_date.in_time_zone)
    create(:payment, candidate_assignment: assignment, status_code: 'failed', paid_at: nil)

    result = described_class.call(reference_date:)
    by_date = result.fetch(:paid_payments).index_by { |row| row.fetch(:date) }

    expect(by_date.fetch(reference_date.iso8601).fetch(:count)).to eq(1)
  end

  it 'counts mobilizations by their mobilized_on date' do
    assignment = create(:candidate_assignment)
    create(:candidate_flight_detail, :mobilized, candidate_assignment: assignment,
                                                 flight_departure_at: reference_date.in_time_zone - 7.days,
                                                 mobilized_on: reference_date)

    result = described_class.call(reference_date:)
    by_date = result.fetch(:mobilized).index_by { |row| row.fetch(:date) }

    expect(by_date.fetch(reference_date.iso8601).fetch(:count)).to eq(1)
  end

  it 'excludes activity outside the 14-day window' do
    create(:candidate, created_at: (reference_date - 20.days).in_time_zone)

    result = described_class.call(reference_date:)

    expect(result.fetch(:active_candidates)).to all(include(count: 0))
  end
end
