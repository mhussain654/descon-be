# frozen_string_literal: true

module Candidates
  module BankDetails
    class UpsertService < ApplicationService
      ALLOWED_CONTENT_TYPES = Candidates::Documents::UploadService::ALLOWED_CONTENT_TYPES
      MAX_FILE_BYTES = ENV.fetch('CANDIDATE_DOCUMENT_MAX_BYTES', 5.megabytes).to_i

      def initialize(candidate:, account_title:, account_number:, bank_name:, proof:, request_id:)
        @candidate = candidate
        @account_title = account_title.to_s
        @account_number = account_number.to_s
        @bank_name = bank_name.to_s
        @proof = proof
        @request_id = request_id
      end

      def call
        blob = nil

        validate_request!
        file_details = Candidates::Documents::UploadedFileInspector.call(uploaded_file: @proof)
        raise UnsupportedFileTypeError unless ALLOWED_CONTENT_TYPES.include?(file_details.content_type)

        blob = build_blob(file_details)
        persist!(file_details:, blob:)
      rescue StandardError
        purge_blob(blob)
        raise
      end

      private

      def validate_request!
        raise NoCurrentAssignmentError if current_assignment.blank?
        raise MissingAccountTitleError if normalized_account_title.blank?
        raise MissingAccountNumberError if normalized_account_number.blank?
        raise InvalidAccountNumberError unless CandidateBankDetail::ACCOUNT_NUMBER_FORMAT.match?(normalized_account_number)
        raise MissingBankNameError if normalized_bank_name.blank?
        raise MissingBankProofError if @proof.blank?
        raise EmptyFileError if @proof.size.to_i.zero?
        raise FileTooLargeError if @proof.size.to_i > MAX_FILE_BYTES
      end

      def current_assignment
        @current_assignment ||= @candidate.current_assignment
      end

      def persist!(file_details:, blob:)
        bank_detail = nil
        replaced = false

        CandidateBankDetail.transaction do
          current_assignment.with_lock do
            current_record = locked_current_record
            supersede_current_record!(current_record)
            bank_detail = create_bank_detail!(file_details:, blob:)
            create_audit_event!(bank_detail:, replaced: current_record.present?)
            replaced = current_record.present?
          end
        end

        Result.new(bank_detail:, replaced:)
      end

      def locked_current_record
        current_assignment.candidate_bank_details.current_version.lock.first
      end

      def supersede_current_record!(current_record)
        return if current_record.blank?

        current_record.update!(superseded_at: Time.current)
      end

      def create_bank_detail!(file_details:, blob:)
        bank_detail = current_assignment.candidate_bank_details.new(
          account_title: normalized_account_title,
          account_number: normalized_account_number,
          bank_name: normalized_bank_name,
          proof_filename: file_details.filename,
          proof_content_type: file_details.content_type,
          proof_byte_size: file_details.byte_size,
          proof_checksum_sha256: file_details.checksum_sha256,
          submitted_at: Time.current
        )
        bank_detail.proof.attach(blob)
        bank_detail.save!
        bank_detail
      end

      def create_audit_event!(bank_detail:, replaced:)
        AuditEvent.create!(
          candidate: @candidate,
          candidate_assignment: current_assignment,
          entity_type: 'CandidateBankDetail',
          entity_id: bank_detail.id,
          action_code: replaced ? 'candidate_bank_detail_updated' : 'candidate_bank_detail_submitted',
          request_id: @request_id,
          metadata: {
            candidate_public_id: @candidate.public_id,
            candidate_assignment_public_id: current_assignment.public_id,
            bank_detail_public_id: bank_detail.public_id
          },
          occurred_at: Time.current
        )
      end

      def build_blob(file_details)
        tempfile = @proof.tempfile
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
        @normalized_account_title ||= @account_title.strip.squish
      end

      def normalized_account_number
        @normalized_account_number ||= AccountNumberNormalizer.call(account_number: @account_number)
      end

      def normalized_bank_name
        @normalized_bank_name ||= @bank_name.strip.squish
      end
    end
  end
end
