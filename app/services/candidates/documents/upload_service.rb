# frozen_string_literal: true

module Candidates
  module Documents
    class UploadService < ApplicationService
      ALLOWED_CONTENT_TYPES = %w[application/pdf image/jpeg image/png].freeze
      MAX_FILE_BYTES = ENV.fetch('CANDIDATE_DOCUMENT_MAX_BYTES', 5.megabytes).to_i

      def initialize(candidate:, uploaded_file:, requirement_code:, request_id:)
        @candidate = candidate
        @uploaded_file = uploaded_file
        @requirement_code = requirement_code.to_s.strip.downcase
        @request_id = request_id
      end

      def call
        blob = nil

        validate_upload_request!
        file_details = UploadedFileInspector.call(uploaded_file: @uploaded_file)

        raise UnsupportedFileTypeError unless ALLOWED_CONTENT_TYPES.include?(file_details.content_type)

        blob = build_blob
        uploaded_document = persist_upload(file_details:, blob:)
        ChecklistItemBuilder.call(requirement:, document: uploaded_document)
      rescue StandardError
        purge_blob(blob)
        raise
      end

      private

      def validate_upload_request!
        raise MissingFileError if @uploaded_file.blank?
        raise EmptyFileError if @uploaded_file.size.to_i.zero?
        raise FileTooLargeError if @uploaded_file.size.to_i > MAX_FILE_BYTES
        raise InvalidRequirementError if requirement.blank?
      end

      def requirement
        @requirement ||= RequirementResolver.call(candidate: @candidate).find do |resolved_requirement|
          resolved_requirement.document_type.code == @requirement_code
        end
      end

      def build_blob
        tempfile = @uploaded_file.tempfile
        tempfile.rewind

        ActiveStorage::Blob.create_and_upload!(
          io: tempfile,
          filename: uploaded_filename,
          content_type: inspected_file_details.content_type,
          identify: false
        )
      ensure
        tempfile&.rewind
      end

      def purge_blob(blob)
        return if blob.blank?
        return if blob.attachments.exists?

        blob.purge
      rescue ActiveRecord::RecordNotFound
        nil
      end

      def persist_upload(file_details:, blob:)
        UploadPersistence.call(
          candidate: @candidate,
          requirement:,
          file_details:,
          blob:,
          request_id: @request_id
        )
      end

      def inspected_file_details
        @inspected_file_details ||= UploadedFileInspector.call(uploaded_file: @uploaded_file)
      end

      def uploaded_filename
        inspected_file_details.filename
      end
    end
  end
end
