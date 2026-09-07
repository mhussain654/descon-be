# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::ReportTable do
  it 'flattens an array-shaped report (status_summary) using its declared column order' do
    data = [{ code: 'registered', position: 1, count: 2 }, { code: 'verified', position: 5, count: 1 }]

    table = described_class.for('status_summary', data)

    expect(table).to eq(headers: %w[code position count], rows: [['registered', 1, 2], ['verified', 5, 1]])
  end

  it 'flattens the mobilization hash-of-arrays into a single dimension-tagged table' do
    data = {
      by_country: [{ code: 'pk', name: 'Pakistan', count: 2 }],
      by_project: [{ code: 'p1', name: 'Project One', count: 3 }]
    }

    table = described_class.for('mobilization', data)

    expect(table).to eq(
      headers: %w[dimension code name count],
      rows: [
        ['country', 'pk', 'Pakistan', 2],
        ['project', 'p1', 'Project One', 3]
      ]
    )
  end

  it 'flattens the outcome_tracking flat hash into a single row' do
    data = { rejected_documents: 1, qvc_re_medical: 0, qvc_rejected: 0, qvc_no_show: 0, visa_rejected: 1 }

    table = described_class.for('outcome_tracking', data)

    expect(table).to eq(
      headers: %w[rejected_documents qvc_re_medical qvc_rejected qvc_no_show visa_rejected],
      rows: [[1, 0, 0, 0, 1]]
    )
  end

  it 'flattens the conversion funnel' do
    data = [{ code: 'verified', count: 2, percentage: 50.0 }]

    table = described_class.for('conversion', data)

    expect(table).to eq(headers: %w[code count percentage], rows: [['verified', 2, 50.0]])
  end

  it 'flattens the trend series' do
    data = [{ period: '2026-06-01', count: 3 }]

    expect(described_class.for('trend', data)).to eq(headers: %w[period count], rows: [['2026-06-01', 3]])
  end
end
