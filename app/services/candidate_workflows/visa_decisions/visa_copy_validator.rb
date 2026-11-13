# frozen_string_literal: true

module CandidateWorkflows
  module VisaDecisions
    # Checks the visa file staff upload with a decision, which the candidate later
    # downloads: a PDF, or a scanned JPEG or PNG image -- judged by the file's own
    # content, never its name or declared type -- that is not empty and at most
    # MAX_FILE_BYTES (scans are larger than the 5 MB candidate document limit).
    class VisaCopyValidator < ApplicationService
      FIELD = 'candidate_visa_decision.visa_copy'
      ALLOWED_CONTENT_TYPES = DocumentRequirement::CONTENT_TYPES
      MAX_FILE_BYTES = 10.megabytes

      def initialize(visa_copy:)
        @visa_copy = visa_copy
      end

      def call
        raise MissingFileError.new(field: FIELD) unless @visa_copy.respond_to?(:tempfile)
        raise EmptyFileError.new(field: FIELD) if @visa_copy.size.to_i.zero?
        raise FileTooLargeError.new(field: FIELD) if @visa_copy.size.to_i > MAX_FILE_BYTES
        raise UnsupportedFileTypeError.new(field: FIELD) unless ALLOWED_CONTENT_TYPES.include?(content_type)
      end

      private

      def content_type
        Candidates::Documents::UploadedFileInspector.call(uploaded_file: @visa_copy).content_type
      end
    end
  end
end
