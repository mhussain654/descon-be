# frozen_string_literal: true

module DocumentOcr
  # Isolates the AWS Textract dependency behind one adapter (AGENTS.md:
  # "application code must not directly depend on ... OCR ... APIs"),
  # mirroring Payments::Providers::KuickpayHostedCheckoutAdapter's isolation
  # pattern. Uses AnalyzeDocument with the Queries feature ("What is the
  # date of issue?" / "What is the date of expiry?"). AnalyzeID, Textract's
  # identity-document operation, only supports US driver's licenses and
  # passports, so it cannot read a Pakistani CNIC; Queries works on any
  # layout and was verified against a real CNIC. Printed dates are parsed
  # here (see DATE_FORMATS).
  #
  # Storage here is local Disk in dev/test (no S3 migration needed):
  # the synchronous API accepts raw in-memory image bytes directly, so the
  # caller downloads the ActiveStorage blob and passes its bytes -- no S3
  # object reference required.
  class TextractAdapter
    PROVIDER_NAME = 'aws_textract'
    ISSUE_DATE_ALIAS = 'ISSUE_DATE'
    EXPIRY_DATE_ALIAS = 'EXPIRY_DATE'
    QUERIES = [
      { text: 'What is the date of issue?', alias: ISSUE_DATE_ALIAS },
      { text: 'What is the date of expiry?', alias: EXPIRY_DATE_ALIAS }
    ].freeze
    NO_DATES_MESSAGE = 'Textract found no issue or expiry date in the uploaded document'
    # CNICs print DD.MM.YYYY; passports commonly print "06 DEC 2021".
    DATE_FORMATS = ['%d.%m.%Y', '%d/%m/%Y', '%d-%m-%Y', '%d %b %Y', '%d %B %Y', '%Y-%m-%d'].freeze

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

      response = call_textract(bytes)
      build_result(response)
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
    def call_textract(bytes)
      @client.analyze_document(document: { bytes: }, feature_types: ['QUERIES'], queries_config: { queries: QUERIES })
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

    def build_result(response)
      answers = answers_by_alias(response.blocks || [])
      issued_on = answer_date(answers[ISSUE_DATE_ALIAS])
      expires_on = answer_date(answers[EXPIRY_DATE_ALIAS])
      raise PermanentError, NO_DATES_MESSAGE if issued_on.nil? && expires_on.nil?

      {
        issued_on:,
        expires_on:,
        confidence_issued_on: issued_on && answers[ISSUE_DATE_ALIAS].confidence,
        confidence_expires_on: expires_on && answers[EXPIRY_DATE_ALIAS].confidence
      }
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

    def answer_date(answer)
      text = answer&.text&.strip
      return unless text&.match?(/\d{4}/)

      DATE_FORMATS.each do |format|
        return Date.strptime(text, format)
      rescue ArgumentError
        next
      end
      nil
    end
  end
end
