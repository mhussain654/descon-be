# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::CsvExport do
  it 'renders headers and rows as CSV' do
    csv = described_class.call(headers: %w[code count], rows: [['registered', 3], ['verified', 1]])

    parsed = CSV.parse(csv, headers: true)
    expect(parsed.headers).to eq(%w[code count])
    expect(parsed.map(&:to_h)).to eq(
      [{ 'code' => 'registered', 'count' => '3' }, { 'code' => 'verified', 'count' => '1' }]
    )
  end

  it 'renders an empty body when there are no rows' do
    csv = described_class.call(headers: %w[code count], rows: [])

    expect(CSV.parse(csv, headers: true).map(&:to_h)).to eq([])
  end
end
