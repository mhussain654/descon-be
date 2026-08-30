# frozen_string_literal: true

module Candidates
  module BankDetails
    class RecordPersister < ApplicationService
      Context = Data.define(:candidate, :current_assignment, :attributes, :file_details, :blob, :request_id)

      def initialize(context:)
        @context = context
      end

      def call
        result = nil

        CandidateBankDetail.transaction do
          current_assignment.with_lock do
            current_record = locked_current_record
            supersede_current_record!(current_record)
            result = persist_current_version!(current_record:)
          end
        end

        result
      end

      private

      def locked_current_record
        current_assignment.candidate_bank_details.current_version.lock.first
      end

      def supersede_current_record!(current_record)
        return if current_record.blank?

        current_record.update!(superseded_at: Time.current)
      end

      def persist_current_version!(current_record:)
        bank_detail = create_bank_detail!
        replaced = current_record.present?
        create_audit_event!(bank_detail:, replaced:)

        Result.new(bank_detail:, replaced:)
      end

      def create_bank_detail!
        bank_detail = current_assignment.candidate_bank_details.new(bank_detail_attributes)
        bank_detail.proof.attach(blob)
        bank_detail.save!
        bank_detail
      end

      def bank_detail_attributes
        {
          account_title: normalized_account_title,
          account_number: normalized_account_number,
          bank_name: normalized_bank_name,
          proof_filename: file_details.filename,
          proof_content_type: file_details.content_type,
          proof_byte_size: file_details.byte_size,
          proof_checksum_sha256: file_details.checksum_sha256,
          submitted_at: Time.current
        }
      end

      def create_audit_event!(bank_detail:, replaced:)
        AuditEvent.create!(
          candidate: candidate,
          candidate_assignment: current_assignment,
          entity_type: 'CandidateBankDetail',
          entity_id: bank_detail.id,
          action_code: replaced ? 'candidate_bank_detail_updated' : 'candidate_bank_detail_submitted',
          request_id: request_id,
          metadata: audit_metadata(bank_detail:),
          occurred_at: Time.current
        )
      end

      def audit_metadata(bank_detail:)
        {
          candidate_public_id: candidate.public_id,
          candidate_assignment_public_id: current_assignment.public_id,
          bank_detail_public_id: bank_detail.public_id
        }
      end

      def candidate
        @context.candidate
      end

      def current_assignment
        @context.current_assignment
      end

      def normalized_account_title
        @normalized_account_title ||= attributes.account_title.to_s.strip.squish
      end

      def normalized_account_number
        @normalized_account_number ||= AccountNumberNormalizer.call(account_number: attributes.account_number)
      end

      def normalized_bank_name
        @normalized_bank_name ||= attributes.bank_name.to_s.strip.squish
      end

      def attributes
        @context.attributes
      end

      def file_details
        @context.file_details
      end

      def blob
        @context.blob
      end

      def request_id
        @context.request_id
      end
    end
  end
end
