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
end
