# frozen_string_literal: true

require 'digest'

module Candidates
  module Documents
    # Identifies one document-upload request's content, so a retried
    # Idempotency-Key with a materially different upload (another file, side
    # label, requirement or issue date) is detected. `uploaded_files` are
    # `{ file:, side_code: }`.
    class UploadFingerprint < ApplicationService
      def initialize(request:, uploaded_files:, requirement_code:, issued_on:)
        @request = request
        @uploaded_files = Array(uploaded_files)
        @requirement_code = requirement_code.to_s.strip.downcase
        @issued_on = issued_on.to_s.strip
      end

      def call
        Digest::SHA256.hexdigest(fingerprint_parts.join("\n"))
      end

      private

      def fingerprint_parts
        [@request.request_method, @request.path, @requirement_code, @issued_on] +
          @uploaded_files.flat_map { |entry| file_parts(entry) }
      end

      def file_parts(entry)
        file = entry[:file]
        side_code = entry[:side_code].to_s.strip.downcase
        return [side_code, '', 0, ''] unless file.respond_to?(:tempfile)

        [side_code, File.basename(file.original_filename.to_s), file.size.to_i, checksum(file)]
      end

      def checksum(file)
        tempfile = file.tempfile
        tempfile.rewind
        Digest::SHA256.file(tempfile.path).hexdigest
      ensure
        tempfile&.rewind
      end
    end
  end
end
