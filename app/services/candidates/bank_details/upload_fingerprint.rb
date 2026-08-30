# frozen_string_literal: true

require 'digest'

module Candidates
  module BankDetails
    class UploadFingerprint < ApplicationService
      def initialize(request:, uploaded_file:, account_title:, account_number:, bank_name:)
        @request = request
        @uploaded_file = uploaded_file
        @account_title = account_title.to_s.strip.squish
        @account_number = AccountNumberNormalizer.call(account_number:)
        @bank_name = bank_name.to_s.strip.squish
      end

      def call
        Digest::SHA256.hexdigest(fingerprint_parts.join("\n"))
      end

      private

      def fingerprint_parts
        [
          @request.request_method,
          @request.path,
          secure_digest(@account_title),
          secure_digest(@account_number),
          secure_digest(@bank_name),
          sanitized_filename,
          file_size,
          file_checksum
        ]
      end

      def secure_digest(value)
        Digest::SHA256.hexdigest(value.to_s)
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
