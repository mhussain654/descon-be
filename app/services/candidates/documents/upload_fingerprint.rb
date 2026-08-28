# frozen_string_literal: true

require 'digest'

module Candidates
  module Documents
    class UploadFingerprint < ApplicationService
      def initialize(request:, uploaded_file:, requirement_code:, issued_on:)
        @request = request
        @uploaded_file = uploaded_file
        @requirement_code = requirement_code.to_s.strip.downcase
        @issued_on = issued_on.to_s.strip
      end

      def call
        Digest::SHA256.hexdigest(fingerprint_parts.join("\n"))
      end

      private

      def fingerprint_parts
        [
          @request.request_method,
          @request.path,
          @requirement_code,
          @issued_on,
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
