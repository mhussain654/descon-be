# frozen_string_literal: true

require 'digest'

module Candidates
  module Documents
    class UploadFingerprint < ApplicationService
      def initialize(request:, uploaded_file:, requirement_code:)
        @request = request
        @uploaded_file = uploaded_file
        @requirement_code = requirement_code.to_s.strip.downcase
      end

      def call
        Digest::SHA256.hexdigest(fingerprint_parts.join("\n"))
      end

      private

      def fingerprint_parts
        [
          @request.request_method,
          @request.path,
          @request.headers['Authorization'].to_s,
          @requirement_code,
          sanitized_filename,
          file_size,
          file_checksum
        ]
      end

      def sanitized_filename
        File.basename(@uploaded_file.original_filename.to_s)
      end

      def file_size
        @uploaded_file.size.to_i
      end

      def file_checksum
        tempfile = @uploaded_file.tempfile
        tempfile.rewind
        Digest::SHA256.file(tempfile.path).hexdigest
      ensure
        tempfile&.rewind
      end
    end
  end
end
