# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::Documents::ExtractDatesJob, type: :job do
  include ActiveJob::TestHelper

  def passport_document
    document_type = DocumentType.find_or_create_by!(code: 'passport') do |type|
      type.name_en = 'Passport'
      type.name_ur = 'پاسپورٹ'
      type.requires_number = true
      type.requires_expiry = true
    end
    create(:candidate_document, document_type:)
  end

  it 'creates a pending extraction, then records the adapter result as succeeded' do
    document = passport_document
    result = {
      issued_on: Date.new(2020, 1, 1), expires_on: Date.new(2030, 1, 1),
      confidence_issued_on: 96.4, confidence_expires_on: 95.1,
      raw_fields: [{ type: 'DATE_OF_ISSUE', value: '01 JAN 2020', confidence: 96.4 }]
    }
    adapter = instance_double(DocumentOcr::TextractAdapter, extract: result)
    allow(DocumentOcr::TextractAdapter).to receive(:new).and_return(adapter)

    described_class.perform_now(document.id)

    extraction = document.document_extractions.sole
    expect(extraction.status).to eq('succeeded')
    expect(extraction.extracted_issued_on).to eq(Date.new(2020, 1, 1))
    expect(extraction.extracted_expires_on).to eq(Date.new(2030, 1, 1))
    expect(extraction.confidence_issued_on).to eq(96.4)
    expect(extraction.confidence_expires_on).to eq(95.1)
    expect(extraction.raw_response).to eq('fields' => [{ 'type' => 'DATE_OF_ISSUE', 'value' => '01 JAN 2020',
                                                         'confidence' => 96.4 }])
    expect(extraction.extracted_at).to be_present
  end

  it 'is idempotent: does not call the adapter again when a pending/succeeded extraction already exists' do
    document = passport_document
    create(:document_extraction, candidate_document: document, status: 'pending')
    adapter = instance_double(DocumentOcr::TextractAdapter)
    allow(adapter).to receive(:extract)
    allow(DocumentOcr::TextractAdapter).to receive(:new).and_return(adapter)

    described_class.perform_now(document.id)

    expect(adapter).not_to have_received(:extract)
    expect(document.document_extractions.count).to eq(1)
  end

  it 'allows a fresh attempt after a prior extraction failed' do
    document = passport_document
    create(:document_extraction, :failed, candidate_document: document)
    result = { issued_on: nil, expires_on: nil, confidence_issued_on: nil, confidence_expires_on: nil, raw_fields: [] }
    adapter = instance_double(DocumentOcr::TextractAdapter, extract: result)
    allow(DocumentOcr::TextractAdapter).to receive(:new).and_return(adapter)

    described_class.perform_now(document.id)

    expect(document.document_extractions.count).to eq(2)
    expect(document.document_extractions.latest_first.first.status).to eq('succeeded')
  end

  it 'marks the extraction failed and schedules a retry on a transient (retryable) error' do
    document = passport_document
    adapter = instance_double(DocumentOcr::TextractAdapter)
    allow(adapter).to receive(:extract).and_raise(DocumentOcr::TransientError, 'throttled')
    allow(DocumentOcr::TextractAdapter).to receive(:new).and_return(adapter)

    expect { described_class.perform_now(document.id) }.to have_enqueued_job(described_class).with(document.id)

    extraction = document.document_extractions.sole
    expect(extraction.status).to eq('failed')
    expect(extraction.error_message).to eq('throttled')
  end

  it 'marks the extraction failed without raising on a permanent error' do
    document = passport_document
    adapter = instance_double(DocumentOcr::TextractAdapter)
    allow(adapter).to receive(:extract).and_raise(DocumentOcr::PermanentError, 'unsupported document')
    allow(DocumentOcr::TextractAdapter).to receive(:new).and_return(adapter)

    expect { described_class.perform_now(document.id) }.not_to raise_error

    extraction = document.document_extractions.sole
    expect(extraction.status).to eq('failed')
    expect(extraction.error_message).to eq('unsupported document')
  end
end
