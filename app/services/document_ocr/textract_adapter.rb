# frozen_string_literal: true

module DocumentOcr
  # Isolates the AWS Textract dependency behind one adapter (AGENTS.md:
  # "application code must not directly depend on ... OCR ... APIs"),
  # mirroring Payments::Providers::KuickpayHostedCheckoutAdapter's isolation
  # pattern. Uses AnalyzeDocument with the Queries feature ("What is the
  # date of issue?" / "What is the date of expiry?"). AnalyzeID, Textract's
  # identity-document operation, only supports US driver's licenses and
  # passports, so it cannot read a Pakistani CNIC; Queries works on any
  # layout and was verified against a real CNIC. Printed dates are parsed by
  # PrintedDate.
  #
  # The birth date is also asked, only to rule it out: DatePicker chooses the
  # dates (a passport's MRZ, and dropping answers that cannot be right).
  #
  # Storage here is local Disk in dev/test (no S3 migration needed):
  # the synchronous API accepts raw in-memory image bytes directly, so the
  # caller downloads the ActiveStorage blob and passes its bytes -- no S3
  # object reference required.
  class TextractAdapter
    PROVIDER_NAME = 'aws_textract'
    ISSUE_DATE_ALIAS = 'ISSUE_DATE'
    EXPIRY_DATE_ALIAS = 'EXPIRY_DATE'
    BIRTH_DATE_ALIAS = 'BIRTH_DATE'
    QUERIES = [
      { text: 'What is the date of issue?', alias: ISSUE_DATE_ALIAS },
      { text: 'What is the date of expiry?', alias: EXPIRY_DATE_ALIAS },
      { text: 'What is the date of birth?', alias: BIRTH_DATE_ALIAS }
    ].freeze
    NO_DATES_MESSAGE = 'Textract found no issue or expiry date in the uploaded document'
    NOT_CONFIGURED_MESSAGE = 'AWS Textract is not configured (DOCUMENT_OCR_ENABLED is not true)'

    RETRYABLE_ERRORS = [
      Aws::Textract::Errors::ThrottlingException,
      Aws::Textract::Errors::ProvisionedThroughputExceededException,
      Aws::Textract::Errors::InternalServerError,
      Aws::Textract::Errors::LimitExceededException,
      Aws::Textract::Errors::ServiceQuotaExceededException,
      Seahorse::Client::NetworkingError
    ].freeze

    def self.enabled? = ENV.fetch('DOCUMENT_OCR_ENABLED', 'false') == 'true'

    def initialize(client: default_client)
      @client = client
    end

    def extract(bytes:)
      unless self.class.enabled?
        raise PermanentError,
              'AWS Textract is not configured (DOCUMENT_OCR_ENABLED is not true)'
      end

      response = call_textract(bytes, QUERIES)
      build_result(response)
    end

    # The page's text lines and the answers to the given queries, for documents
    # that are compared with what we already know rather than read for dates
    # (a boarding pass). Returns { lines: [String], answers: { alias => String } };
    # the caller must not store either.
    def read_text(bytes:, queries:)
      raise PermanentError, NOT_CONFIGURED_MESSAGE unless self.class.enabled?

      blocks = call_textract(bytes, queries).blocks || []
      { lines: text_lines(blocks).map(&:first),
        answers: answers_by_alias(blocks).transform_values { |answer| answer&.text }.compact }
    end

    private

    def default_client
      timeout = Integer(ENV.fetch('DOCUMENT_OCR_TIMEOUT_SECONDS', '10'))
      Aws::Textract::Client.new(http_open_timeout: timeout, http_read_timeout: timeout)
    end

    # Never persists the raw AWS SDK exception message (potentially carrying
    # request internals) into DocumentExtraction#error_message, which the
    # HR review UI displays as-is (Admin::DocumentExtractionSerializer) --
    # only a fixed, provider-agnostic message plus the exception's class
    # name (a stable, non-sensitive identifier). The real message is still
    # logged server-side for support/debugging, never persisted or exposed.
    def call_textract(bytes, queries)
      @client.analyze_document(document: { bytes: }, feature_types: ['QUERIES'], queries_config: { queries: })
    rescue *RETRYABLE_ERRORS => e
      raise TransientError, sanitized_provider_error('transient', e)
    rescue Aws::Textract::Errors::ServiceError => e
      raise PermanentError, sanitized_provider_error('permanent', e)
    end

    def sanitized_provider_error(kind, error)
      Rails.logger.warn("[DocumentOcr::TextractAdapter] #{kind} failure (#{error.class}): #{error.message}")
      action = kind == 'transient' ? 'failed transiently' : 'rejected the request'
      "AWS Textract #{action} (#{error.class.name.demodulize})"
    end

    # The dates, plus whether the page looks like an ID at all (IdentityMarkers).
    def build_result(response)
      blocks = response.blocks || []
      lines = text_lines(blocks)
      picked = DatePicker.call(answers: answers(blocks), lines:)
      identity = IdentityMarkers.call(lines: lines.map(&:first))
      raise NoDatesError.new(NO_DATES_MESSAGE, identity:) if picked[:issue].nil? && picked[:expiry].nil?

      dates_result(picked[:issue], picked[:expiry]).merge(identity:)
    end

    def dates_result(issue, expiry)
      { issued_on: issue&.first, expires_on: expiry&.first,
        confidence_issued_on: issue&.last, confidence_expires_on: expiry&.last }
    end

    # Each query's answer as [text, confidence] (nil when unanswered).
    def answers(blocks)
      by_alias = answers_by_alias(blocks)
      { issue: ISSUE_DATE_ALIAS, expiry: EXPIRY_DATE_ALIAS, birth: BIRTH_DATE_ALIAS }.transform_values do |name|
        answer = by_alias[name]
        answer && [answer.text, answer.confidence]
      end
    end

    # The page's text lines with their confidence, read only to find a passport MRZ.
    def text_lines(blocks)
      blocks.select { |block| block.block_type == 'LINE' }.map { |block| [block.text, block.confidence] }
    end

    # Maps each query alias to its answer block, discarding every other block
    # (the raw page text is never kept).
    def answers_by_alias(blocks)
      results = blocks.select { |block| block.block_type == 'QUERY_RESULT' }.index_by(&:id)
      blocks.select { |block| block.block_type == 'QUERY' }.to_h do |query|
        [query.query.alias, results[answer_id(query)]]
      end
    end

    def answer_id(query)
      query.relationships&.find { |relationship| relationship.type == 'ANSWER' }&.ids&.first
    end
  end
end
