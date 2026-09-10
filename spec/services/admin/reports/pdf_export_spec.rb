# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Reports::PdfExport do
  it 'renders a valid PDF document' do
    binary = described_class.call(headers: %w[code count], rows: [['registered', 3], ['verified', 1]])

    expect(binary[0..4]).to eq('%PDF-')
  end

  it 'renders an empty body without raising' do
    expect { described_class.call(headers: %w[code count], rows: []) }.not_to raise_error
  end
end
