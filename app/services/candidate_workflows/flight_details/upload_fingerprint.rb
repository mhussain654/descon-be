# frozen_string_literal: true

require 'digest'

module CandidateWorkflows
  module FlightDetails
    class UploadFingerprint < ApplicationService
      def initialize(request:, candidate_public_id:, payload:, uploaded_file:)
        @request = request
        @candidate_public_id = candidate_public_id
        @payload = payload
        @uploaded_file = uploaded_file
      end

      def call
        Digest::SHA256.hexdigest(fingerprint_parts.join("\n"))
      end

      private

      def fingerprint_parts
        [
          @request.request_method,
          @request.path,
          @candidate_public_id,
          @payload.to_json,
          sanitized_filename,
          file_size,
          file_checksum
        ]
      end

      def sanitized_filename
        return '' if @uploaded_file.blank?

        File.basename(@uploaded_file.original_filename.to_s)
      end

      def file_size
        return 0 if @uploaded_file.blank?

        @uploaded_file.size.to_i
      end

      def file_checksum
        return '' if @uploaded_file.blank?

        tempfile = @uploaded_file.tempfile
        tempfile.rewind
        Digest::SHA256.file(tempfile.path).hexdigest
      ensure
        tempfile&.rewind
      end
    end
  end
end
