# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentOcr::TextractAdapter do
  around do |example|
    original = ENV.fetch('DOCUMENT_OCR_ENABLED', nil)
    ENV['DOCUMENT_OCR_ENABLED'] = 'true'
    example.run
    ENV['DOCUMENT_OCR_ENABLED'] = original
  end

  def detection(text:, confidence: 98.0, normalized_value: nil)
    Aws::Textract::Types::AnalyzeIDDetections.new(text:, confidence:, normalized_value:)
  end

  def field(type:, value_text:, value_confidence: 97.0, normalized_date: nil)
    normalized_value = normalized_date && Aws::Textract::Types::NormalizedValue.new(value: normalized_date,
                                                                                    value_type: 'Date')
    Aws::Textract::Types::IdentityDocumentField.new(
      type: detection(text: type),
      value_detection: detection(text: value_text, confidence: value_confidence, normalized_value:)
    )
  end

  def response_with(fields)
    Aws::Textract::Types::AnalyzeIDResponse.new(
      identity_documents: [Aws::Textract::Types::IdentityDocument.new(document_index: 1,
                                                                      identity_document_fields: fields)]
    )
  end

  describe '.enabled?' do
    it 'reflects the DOCUMENT_OCR_ENABLED env var' do
      ENV['DOCUMENT_OCR_ENABLED'] = 'true'
      expect(described_class.enabled?).to be(true)

      ENV['DOCUMENT_OCR_ENABLED'] = 'false'
      expect(described_class.enabled?).to be(false)
    end
  end

  describe '#extract' do
    it 'raises PermanentError without calling the client when OCR is disabled' do
      ENV['DOCUMENT_OCR_ENABLED'] = 'false'
      client = instance_double(Aws::Textract::Client, analyze_id: nil)
      adapter = described_class.new(client:)

      expect { adapter.extract(bytes: 'x') }.to raise_error(DocumentOcr::PermanentError)
      expect(client).not_to have_received(:analyze_id)
    end

    it 'extracts normalized issue/expiry dates and confidences from the identity document fields' do
      fields = [
        field(type: 'DATE_OF_ISSUE', value_text: '01 JAN 2020', value_confidence: 96.4, normalized_date: '2020-01-01'),
        field(type: 'EXPIRATION_DATE', value_text: '01 JAN 2030', value_confidence: 95.1,
              normalized_date: '2030-01-01'),
        field(type: 'DOCUMENT_NUMBER', value_text: '12345-6789012-3')
      ]
      client = instance_double(Aws::Textract::Client, analyze_id: response_with(fields))
      adapter = described_class.new(client:)

      result = adapter.extract(bytes: 'image-bytes')

      expect(result).to eq(
        issued_on: Date.new(2020, 1, 1),
        expires_on: Date.new(2030, 1, 1),
        confidence_issued_on: 96.4,
        confidence_expires_on: 95.1
      )
      expect(client).to have_received(:analyze_id).with(document_pages: [{ bytes: 'image-bytes' }])
    end

    it 'discards every unrelated identity field Textract returns -- only issue/expiry dates and confidences survive' do
      fields = [
        field(type: 'DATE_OF_ISSUE', value_text: '01 JAN 2020', normalized_date: '2020-01-01'),
        field(type: 'EXPIRATION_DATE', value_text: '01 JAN 2030', normalized_date: '2030-01-01'),
        field(type: 'FIRST_NAME', value_text: 'Ahmed'),
        field(type: 'LAST_NAME', value_text: 'Khan'),
        field(type: 'DATE_OF_BIRTH', value_text: '01 JAN 1990'),
        field(type: 'DOCUMENT_NUMBER', value_text: '12345-6789012-3'),
        field(type: 'ADDRESS', value_text: '123 Main Street, Karachi'),
        field(type: 'PLACE_OF_BIRTH', value_text: 'Karachi'),
        field(type: 'MRZ_CODE', value_text: 'P<PAKKHAN<<AHMED<<<<<<<<<<<<<<<<<<<<<<<<<<<')
      ]
      client = instance_double(Aws::Textract::Client, analyze_id: response_with(fields))
      adapter = described_class.new(client:)

      result = adapter.extract(bytes: 'image-bytes')

      expect(result.keys).to contain_exactly(:issued_on, :expires_on, :confidence_issued_on, :confidence_expires_on)
      expect(result.values.join).not_to match(/Ahmed|Khan|Karachi|Main Street|MRZ|PAKKHAN/)
    end

    it 'leaves a date nil when its field is missing entirely' do
      client = instance_double(Aws::Textract::Client,
                               analyze_id: response_with([field(type: 'DOCUMENT_NUMBER', value_text: 'x')]))
      adapter = described_class.new(client:)

      result = adapter.extract(bytes: 'x')

      expect(result[:issued_on]).to be_nil
      expect(result[:expires_on]).to be_nil
    end

    it 'leaves a date nil when Textract could not normalize it, without raising' do
      client = instance_double(
        Aws::Textract::Client,
        analyze_id: response_with([field(type: 'DATE_OF_ISSUE', value_text: 'illegible', normalized_date: nil)])
      )
      adapter = described_class.new(client:)

      expect(adapter.extract(bytes: 'x')[:issued_on]).to be_nil
    end

    it 'raises PermanentError when Textract detects no identity document' do
      client = instance_double(
        Aws::Textract::Client,
        analyze_id: Aws::Textract::Types::AnalyzeIDResponse.new(identity_documents: [])
      )
      adapter = described_class.new(client:)

      expect { adapter.extract(bytes: 'x') }.to raise_error(DocumentOcr::PermanentError, /no identity document/)
    end

    it 'raises TransientError on a throttling error, with a sanitized message that drops the raw provider text' do
      client = instance_double(Aws::Textract::Client)
      allow(client).to receive(:analyze_id).and_raise(
        Aws::Textract::Errors::ThrottlingException.new(nil, 'slow down, request-id abc123, bucket s3://internal-bucket')
      )
      adapter = described_class.new(client:)

      expect { adapter.extract(bytes: 'x') }.to raise_error(DocumentOcr::TransientError) do |error|
        expect(error.message).not_to include('slow down', 'internal-bucket', 'abc123')
        expect(error.message).to include('ThrottlingException')
      end
    end

    it 'raises TransientError on a networking error' do
      client = instance_double(Aws::Textract::Client)
      allow(client).to receive(:analyze_id).and_raise(Seahorse::Client::NetworkingError.new(StandardError.new('timeout')))
      adapter = described_class.new(client:)

      expect { adapter.extract(bytes: 'x') }.to raise_error(DocumentOcr::TransientError)
    end

    it 'raises PermanentError on an unsupported-document error, sanitized to drop the raw provider text' do
      error = Aws::Textract::Errors::UnsupportedDocumentException.new(nil, 'bad format, saw request-id xyz789')
      client = instance_double(Aws::Textract::Client)
      allow(client).to receive(:analyze_id).and_raise(error)
      adapter = described_class.new(client:)

      expect { adapter.extract(bytes: 'x') }.to raise_error(DocumentOcr::PermanentError) do |raised|
        expect(raised.message).not_to include('bad format', 'xyz789')
        expect(raised.message).to include('UnsupportedDocumentException')
      end
    end
  end
end
