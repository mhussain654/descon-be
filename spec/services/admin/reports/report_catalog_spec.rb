# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::ReportCatalog do
  it 'lists every known report type' do
    expect(described_class::REPORT_TYPES).to contain_exactly(
      'status_summary', 'mobilization', 'craft_summary', 'outcome_tracking', 'conversion', 'trend'
    )
  end

  it 'dispatches each report type to its query object' do
    described_class::REPORT_TYPES.each do |report_type|
      expect { described_class.data_for(report_type) }.not_to raise_error
    end
  end

  it 'passes a granularity param through to the trend report' do
    result = described_class.data_for('trend', params: { granularity: 'daily' })

    expect(result).to eq([])
  end

  it 'rejects an unknown report type' do
    expect { described_class.data_for('bogus') }
      .to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('report_type') }
  end
end
