# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentOcr::TextractAdapter do
  around do |example|
    original = ENV.fetch('DOCUMENT_OCR_ENABLED', nil)
    ENV['DOCUMENT_OCR_ENABLED'] = 'true'
    example.run
    ENV['DOCUMENT_OCR_ENABLED'] = original
  end

  def answer_blocks(query_alias, text, confidence: 97.0)
    id = "result-#{query_alias}"
    [
      Aws::Textract::Types::Block.new(
        block_type: 'QUERY', query: Aws::Textract::Types::Query.new(text: 'q', alias: query_alias),
        relationships: [Aws::Textract::Types::Relationship.new(type: 'ANSWER', ids: [id])]
      ),
      Aws::Textract::Types::Block.new(block_type: 'QUERY_RESULT', id:, text:, confidence:)
    ]
  end

  def unanswered_query(query_alias)
    Aws::Textract::Types::Block.new(block_type: 'QUERY',
                                    query: Aws::Textract::Types::Query.new(
                                      text: 'q', alias: query_alias
                                    ))
  end

  def response_with(*blocks)
    Aws::Textract::Types::AnalyzeDocumentResponse.new(blocks: blocks.flatten)
  end

  def adapter_for(response)
    described_class.new(client: instance_double(Aws::Textract::Client, analyze_document: response))
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
      client = instance_double(Aws::Textract::Client, analyze_document: nil)

      expect { described_class.new(client:).extract(bytes: 'x') }.to raise_error(DocumentOcr::PermanentError)
      expect(client).not_to have_received(:analyze_document)
    end

    it 'asks the issue and expiry date queries and returns the parsed dates with their confidences' do
      response = response_with(answer_blocks('ISSUE_DATE', '06.12.2021', confidence: 96.4),
                               answer_blocks('EXPIRY_DATE', '06.12.2031', confidence: 95.1))
      client = instance_double(Aws::Textract::Client, analyze_document: response)

      result = described_class.new(client:).extract(bytes: 'image-bytes')

      expect(result).to eq(issued_on: Date.new(2021, 12, 6), expires_on: Date.new(2031, 12, 6),
                           confidence_issued_on: 96.4, confidence_expires_on: 95.1)
      expect(client).to have_received(:analyze_document).with(
        document: { bytes: 'image-bytes' }, feature_types: ['QUERIES'],
        queries_config: { queries: described_class::QUERIES }
      )
    end

    it 'parses the date formats printed on CNICs and passports' do
      {
        '06.12.2021' => Date.new(2021, 12, 6), '06/12/2021' => Date.new(2021, 12, 6),
        '06-12-2021' => Date.new(2021, 12, 6), '06 DEC 2021' => Date.new(2021, 12, 6),
        '06 December 2021' => Date.new(2021, 12, 6), '2021-12-06' => Date.new(2021, 12, 6)
      }.each do |text, expected|
        result = adapter_for(response_with(answer_blocks('ISSUE_DATE', text))).extract(bytes: 'x')
        expect(result[:issued_on]).to eq(expected), "expected #{text} to parse as #{expected}"
      end
    end

    it 'keeps only the dates and confidences, never the other text Textract returns' do
      page = Aws::Textract::Types::Block.new(block_type: 'LINE', text: 'AHMED KHAN 12345-6789012-3')
      response = response_with(page, answer_blocks('ISSUE_DATE', '06.12.2021'),
                               answer_blocks('EXPIRY_DATE', '06.12.2031'))

      result = adapter_for(response).extract(bytes: 'x')

      expect(result.keys).to contain_exactly(:issued_on, :expires_on, :confidence_issued_on, :confidence_expires_on)
      expect(result.values.join).not_to match(/AHMED|KHAN|12345/)
    end

    it 'leaves one date nil when only the other was found' do
      response = response_with(answer_blocks('EXPIRY_DATE', '06.12.2031'), unanswered_query('ISSUE_DATE'))

      result = adapter_for(response).extract(bytes: 'x')

      expect(result[:issued_on]).to be_nil
      expect(result[:confidence_issued_on]).to be_nil
      expect(result[:expires_on]).to eq(Date.new(2031, 12, 6))
    end

    it 'treats an unparseable or implausible answer as no date' do
      response = response_with(answer_blocks('ISSUE_DATE', 'illegible'), answer_blocks('EXPIRY_DATE', '31.02.2031'),
                               answer_blocks('ISSUE_DATE', '21'))

      expect do
        adapter_for(response).extract(bytes: 'x')
      end.to raise_error(DocumentOcr::PermanentError, /no issue or expiry/)
    end

    it 'raises PermanentError when no date can be read at all' do
      expect { adapter_for(response_with).extract(bytes: 'x') }
        .to raise_error(DocumentOcr::PermanentError, /no issue or expiry/)
    end

    it 'raises TransientError on a throttling error, with a sanitized message that drops the raw provider text' do
      client = instance_double(Aws::Textract::Client)
      allow(client).to receive(:analyze_document).and_raise(
        Aws::Textract::Errors::ThrottlingException.new(nil, 'slow down, request-id abc123, bucket s3://internal-bucket')
      )

      expect { described_class.new(client:).extract(bytes: 'x') }.to raise_error(DocumentOcr::TransientError) do |error|
        expect(error.message).not_to include('slow down', 'internal-bucket', 'abc123')
        expect(error.message).to include('ThrottlingException')
      end
    end

    it 'raises TransientError on a networking error' do
      client = instance_double(Aws::Textract::Client)
      allow(client).to receive(:analyze_document)
        .and_raise(Seahorse::Client::NetworkingError.new(StandardError.new('timeout')))

      expect { described_class.new(client:).extract(bytes: 'x') }.to raise_error(DocumentOcr::TransientError)
    end

    it 'raises PermanentError on an unsupported-document error, sanitized to drop the raw provider text' do
      error = Aws::Textract::Errors::UnsupportedDocumentException.new(nil, 'bad format, saw request-id xyz789')
      client = instance_double(Aws::Textract::Client)
      allow(client).to receive(:analyze_document).and_raise(error)

      expect { described_class.new(client:).extract(bytes: 'x') }.to raise_error(DocumentOcr::PermanentError) { |raised|
        expect(raised.message).not_to include('bad format', 'xyz789')
        expect(raised.message).to include('UnsupportedDocumentException')
      }
    end
  end
end
