# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::TrendQuery do
  def mobilized_stage
    WorkflowStage.find_or_create_by!(code: 'mobilized') do |record|
      record.position = 15
      record.system_defined = true
    end
  end

  def mobilization_event(occurred_at:)
    assignment = create(:candidate_assignment)
    create(:candidate_stage_history, candidate_assignment: assignment, to_workflow_stage: mobilized_stage, occurred_at:)
  end

  it 'buckets mobilization events by day' do
    mobilization_event(occurred_at: Time.zone.parse('2026-06-01 09:00:00'))
    mobilization_event(occurred_at: Time.zone.parse('2026-06-01 18:00:00'))
    mobilization_event(occurred_at: Time.zone.parse('2026-06-02 09:00:00'))

    result = described_class.call(granularity: 'daily')

    expect(result).to eq(
      [
        { period: '2026-06-01', count: 2 },
        { period: '2026-06-02', count: 1 }
      ]
    )
  end

  it 'buckets mobilization events by month' do
    mobilization_event(occurred_at: Time.zone.parse('2026-06-01 09:00:00'))
    mobilization_event(occurred_at: Time.zone.parse('2026-06-20 09:00:00'))
    mobilization_event(occurred_at: Time.zone.parse('2026-07-05 09:00:00'))

    result = described_class.call(granularity: 'monthly')

    expect(result).to eq(
      [
        { period: '2026-06-01', count: 2 },
        { period: '2026-07-01', count: 1 }
      ]
    )
  end

  it 'ignores stage-history rows that are not the mobilized destination' do
    assignment = create(:candidate_assignment)
    create(:candidate_stage_history, candidate_assignment: assignment, occurred_at: Time.current)

    expect(described_class.call).to eq([])
  end

  it 'filters by an inclusive from/to date range' do
    mobilization_event(occurred_at: Time.zone.parse('2026-06-01 09:00:00'))
    in_range = mobilization_event(occurred_at: Time.zone.parse('2026-06-15 09:00:00'))
    mobilization_event(occurred_at: Time.zone.parse('2026-07-01 09:00:00'))

    result = described_class.call(granularity: 'daily', from: Date.new(2026, 6, 10), to: Date.new(2026, 6, 20))

    expect(result).to eq([{ period: in_range.occurred_at.to_date.iso8601, count: 1 }])
  end

  it 'rejects an unsupported granularity' do
    expect { described_class.call(granularity: 'yearly') }
      .to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('granularity') }
  end
end
