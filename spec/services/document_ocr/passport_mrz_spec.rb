# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentOcr::PassportMrz do
  # A made-up passport's MRZ second line, with valid check digits for the given dates (YYMMDD).
  def mrz_line(birth:, expiry:, expiry_check: nil)
    "AB12345674PAK#{birth}#{check_digit(birth)}M#{expiry}#{expiry_check || check_digit(expiry)}1234512345671<12"
  end

  def check_digit(digits)
    weights = described_class::WEIGHTS
    digits.chars.each_with_index.sum { |char, index| char.to_i * weights[index % 3] } % 10
  end

  it 'reads the birth and expiry dates, with the line confidence' do
    result = described_class.call(lines: [['P<PAKKHAN<<AYESHA<<<<<<<<<<<<<<<<<<<<<<<<<<<', 99.0],
                                          [mrz_line(birth: '910315', expiry: '281111'), 98.5]])

    expect(result).to eq(birth_date: Date.new(1991, 3, 15), expires_on: Date.new(2028, 11, 11), confidence: 98.5)
  end

  it 'ignores spaces the OCR put inside the line' do
    line = mrz_line(birth: '050101', expiry: '300101').insert(20, ' ')

    expect(described_class.call(lines: [[line, 90.0]])).to include(birth_date: Date.new(2005, 1, 1))
  end

  it 'refuses a line whose check digits do not match (a misread digit)' do
    expect(described_class.call(lines: [[mrz_line(birth: '910315', expiry: '281111', expiry_check: '5'), 99.0]]))
      .to be_nil
  end

  it 'returns nil for a page without an MRZ (e.g. a CNIC)' do
    expect(described_class.call(lines: [['13 NOV 2023', 99.0], ['PAKISTAN', 99.0]])).to be_nil
  end
end
