# frozen_string_literal: true

require 'digest'

module Candidates
  module Documents
    class UploadedFileInspector < ApplicationService
      def initialize(uploaded_file:)
        @uploaded_file = uploaded_file
      end

      def call
        UploadedFileDetails.new(
          filename: sanitized_filename,
          content_type: detected_content_type,
          byte_size: @uploaded_file.size.to_i,
          checksum_sha256: checksum_sha256
        )
      end

      private

      # Decided by the file's own signature (magic bytes) only -- the
      # browser-declared type and the filename extension are never trusted, so
      # a renamed or mislabelled file can't pass as a PDF or image.
      def detected_content_type
        with_tempfile { |tempfile| Marcel::Magic.by_magic(tempfile)&.type || 'application/octet-stream' }
      end

      def checksum_sha256
        with_tempfile { |tempfile| Digest::SHA256.file(tempfile.path).hexdigest }
      end

      def sanitized_filename
        File.basename(@uploaded_file.original_filename.to_s)
      end

      def with_tempfile
        tempfile = @uploaded_file.tempfile
        tempfile.rewind
        yield tempfile
      ensure
        tempfile&.rewind
      end
    end
  end
end
