# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe Admin::Reports::XlsxExport do
  def sheet_xml(binary)
    xml = nil
    Zip::File.open_buffer(StringIO.new(binary)) { |zip| xml = zip.find_entry('xl/worksheets/sheet1.xml').get_input_stream.read }
    xml
  end

  it 'renders a valid xlsx workbook containing the header and row values' do
    binary = described_class.call(headers: %w[code count], rows: [['registered', 3], ['verified', 1]])

    expect(binary[0..1]).to eq('PK')
    xml = sheet_xml(binary)
    expect(xml).to include('registered')
    expect(xml).to include('verified')
  end

  describe 'formula injection (malicious candidate-name/reference-style values)' do
    it 'neutralizes a candidate name starting with =, preventing Excel from treating it as a formula' do
      binary = described_class.call(headers: %w[name count], rows: [['=HYPERLINK("https://evil.example")', 1]])

      xml = sheet_xml(binary)
      # Axlsx XML-escapes the leading apostrophe as a numeric character
      # reference (&#39;) rather than a literal quote.
      expect(xml).to include('&#39;=HYPERLINK')
      expect(xml).not_to include('<f>=HYPERLINK')
    end

    it 'neutralizes values starting with +, -, @, tab or carriage return' do
      binary = described_class.call(
        headers: %w[a b c d e],
        rows: [['+1+1', '-2+3', '@SUM(1)', "\t=1", "\r=1"]]
      )

      xml = sheet_xml(binary)
      %w[+1+1 -2+3 @SUM(1)].each { |value| expect(xml).to include("&#39;#{value}") }
    end

    it 'leaves an ordinary candidate name untouched' do
      binary = described_class.call(headers: %w[name], rows: [['Ahmed Ali']])

      expect(sheet_xml(binary)).to include('Ahmed Ali')
      expect(sheet_xml(binary)).not_to include("'Ahmed Ali")
    end

    it 'leaves a numeric cell as a real typed number, never coerced to a quoted text string' do
      binary = described_class.call(headers: %w[name count], rows: [['Ahmed Ali', -5]])

      xml = sheet_xml(binary)
      expect(xml).to match(%r{<c r="B2"[^>]*><v>-5</v></c>})
    end
  end
end
