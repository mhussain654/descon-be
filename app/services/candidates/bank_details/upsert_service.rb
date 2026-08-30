# frozen_string_literal: true

module Candidates
  module BankDetails
    class UpsertService < ApplicationService
      ALLOWED_CONTENT_TYPES = Candidates::Documents::UploadService::ALLOWED_CONTENT_TYPES
      Attributes = Data.define(:account_title, :account_number, :bank_name, :proof)

      def initialize(candidate:, attributes:, request_id:)
        @candidate = candidate
        @attributes = Attributes.new(**normalized_attributes(attributes))
        @request_id = request_id
      end

      def call
        blob = nil

        validate_request!
        file_details = Candidates::Documents::UploadedFileInspector.call(uploaded_file: proof)
        raise UnsupportedFileTypeError unless ALLOWED_CONTENT_TYPES.include?(file_details.content_type)

        blob = build_blob(file_details)
        persist!(file_details:, blob:)
      rescue StandardError
        purge_blob(blob)
        raise
      end

      private

      def normalized_attributes(attributes)
        {
          account_title: attributes[:account_title],
          account_number: attributes[:account_number],
          bank_name: attributes[:bank_name],
          proof: attributes[:proof]
        }
      end

      def validate_request!
        Candidates::BankDetails::RequestValidator.call(
          candidate: @candidate,
          attributes: @attributes
        )
      end

      def current_assignment
        @current_assignment ||= @candidate.current_assignment
      end

      def persist!(file_details:, blob:)
        Candidates::BankDetails::RecordPersister.call(
          context: Candidates::BankDetails::RecordPersister::Context.new(
            candidate: @candidate,
            current_assignment:,
            attributes: @attributes,
            file_details:,
            blob:,
            request_id: @request_id
          )
        )
      end

      def build_blob(file_details)
        tempfile = proof.tempfile
        tempfile.rewind

        ActiveStorage::Blob.create_and_upload!(
          io: tempfile,
          filename: file_details.filename,
          content_type: file_details.content_type,
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

      def normalized_account_title
        @normalized_account_title ||= @attributes.account_title.to_s.strip.squish
      end

      def proof
        @attributes.proof
      end
    end
  end
end
