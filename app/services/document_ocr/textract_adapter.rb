# frozen_string_literal: true

module DocumentOcr
  # Isolates the AWS Textract dependency behind one adapter (AGENTS.md:
  # "application code must not directly depend on ... OCR ... APIs"),
  # mirroring Payments::Providers::KuickpayHostedCheckoutAdapter's isolation
  # pattern. Uses AnalyzeID -- Textract's operation purpose-built for
  # identity documents (passport/CNIC), returning normalized field types
  # (DATE_OF_ISSUE, EXPIRATION_DATE) directly rather than requiring
  # free-text date parsing.
  #
  # Storage here is local Disk in dev/test (no S3 migration needed):
  # AnalyzeID's synchronous API accepts raw in-memory image bytes directly,
  # so the caller downloads the ActiveStorage blob and passes its bytes --
  # no S3 object reference required.
  class TextractAdapter
    PROVIDER_NAME = 'aws_textract'
    ISSUE_DATE_FIELD_TYPE = 'DATE_OF_ISSUE'
    EXPIRY_DATE_FIELD_TYPE = 'EXPIRATION_DATE'

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

    def call_textract(bytes)
      @client.analyze_id(document_pages: [{ bytes: }])
    rescue *RETRYABLE_ERRORS => e
      raise TransientError, e.message
    rescue Aws::Textract::Errors::ServiceError => e
      raise PermanentError, e.message
    end

    def build_result(response)
      document = response.identity_documents&.first
      raise PermanentError, 'Textract detected no identity document in the uploaded image' if document.blank?

      fields = document.identity_document_fields || []
      {
        issued_on: field_date(fields, ISSUE_DATE_FIELD_TYPE),
        expires_on: field_date(fields, EXPIRY_DATE_FIELD_TYPE),
        confidence_issued_on: field_confidence(fields, ISSUE_DATE_FIELD_TYPE),
        confidence_expires_on: field_confidence(fields, EXPIRY_DATE_FIELD_TYPE),
        raw_fields: normalized_fields(fields)
      }
    end

    def field_for(fields, type)
      fields.find { |field| field.type&.text == type }
    end

    def field_date(fields, type)
      field = field_for(fields, type)
      normalized = field&.value_detection&.normalized_value
      return if normalized.blank? || normalized.value.blank?

      Date.parse(normalized.value)
    rescue ArgumentError, TypeError
      nil
    end

    def field_confidence(fields, type)
      field_for(fields, type)&.value_detection&.confidence
    end

    # Field type/value text only -- never the document's raw block/geometry
    # data, and never a full-document text dump (AGENTS.md: never log or
    # store more sensitive-document content than HR review actually needs).
    def normalized_fields(fields)
      fields.filter_map do |field|
        next if field.type&.text.blank?

        { type: field.type.text, value: field.value_detection&.text, confidence: field.value_detection&.confidence }
      end
    end
  end
end
