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

      def detected_content_type
        with_tempfile do |tempfile|
          Marcel::MimeType.for(
            tempfile,
            name: @uploaded_file.original_filename.to_s,
            declared_type: @uploaded_file.content_type.to_s
          )
        end
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
