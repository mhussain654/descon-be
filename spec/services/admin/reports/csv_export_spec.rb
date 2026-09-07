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

  describe 'formula injection (malicious candidate-name/reference-style values)' do
    it 'neutralizes a candidate name starting with =, preventing Excel/Sheets from treating it as a formula' do
      csv = described_class.call(headers: %w[name count], rows: [['=HYPERLINK("https://evil.example")', 1]])

      row = CSV.parse(csv, headers: true).first
      expect(row['name']).to start_with("'=")
    end

    it 'neutralizes a reference number starting with +' do
      csv = described_class.call(headers: %w[reference count], rows: [['+1+1', 1]])

      expect(CSV.parse(csv, headers: true).first['reference']).to eq("'+1+1")
    end

    it 'neutralizes a value starting with -' do
      csv = described_class.call(headers: %w[name count], rows: [['-2+3+cmd|" /C calc"!A0', 1]])

      expect(CSV.parse(csv, headers: true).first['name']).to start_with("'-")
    end

    it 'neutralizes a value starting with @' do
      csv = described_class.call(headers: %w[name count], rows: [['@SUM(1+1)', 1]])

      expect(CSV.parse(csv, headers: true).first['name']).to eq("'@SUM(1+1)")
    end

    it 'neutralizes a value starting with a tab or carriage return' do
      csv = described_class.call(headers: %w[name count], rows: [["\t=1+1", 1]])

      expect(CSV.parse(csv, headers: true).first['name']).to start_with("'")
    end

    it 'leaves an ordinary candidate name untouched' do
      csv = described_class.call(headers: %w[name count], rows: [['Ahmed Ali', 1]])

      expect(CSV.parse(csv, headers: true).first['name']).to eq('Ahmed Ali')
    end

    it 'leaves a numeric cell as a real number, never coerced to a quoted string' do
      csv = described_class.call(headers: %w[name count], rows: [['Ahmed Ali', -5]])

      expect(CSV.parse(csv, headers: true).first['count']).to eq('-5')
    end
  end
end
