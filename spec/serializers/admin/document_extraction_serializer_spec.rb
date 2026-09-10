# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::DocumentExtractionSerializer do
  it 'reports not_started when no extraction exists yet' do
    expect(described_class.new(nil).as_json).to eq(status: 'not_started')
  end

  it 'serializes a succeeded extraction with normalized dates and confidence' do
    extraction = build(
      :document_extraction, :succeeded,
      extracted_issued_on: Date.new(2020, 1, 1), extracted_expires_on: Date.new(2030, 1, 1),
      confidence_issued_on: 96.4, confidence_expires_on: 95.1
    )

    result = described_class.new(extraction).as_json

    expect(result).to include(
      status: 'succeeded', issued_on: '2020-01-01', expires_on: '2030-01-01',
      confidence_issued_on: 96.4, confidence_expires_on: 95.1
    )
    expect(result).not_to have_key(:error_message)
  end

  it 'includes the error_message only when the extraction failed' do
    extraction = build(:document_extraction, :failed, error_message: 'no identity document detected')

    result = described_class.new(extraction).as_json

    expect(result).to eq(status: 'failed', error_message: 'no identity document detected',
                         extracted_at: result[:extracted_at])
  end

  it 'omits nil date/confidence fields for a still-pending extraction' do
    extraction = build(:document_extraction, status: 'pending')

    expect(described_class.new(extraction).as_json).to eq(status: 'pending')
  end
end
