# frozen_string_literal: true

module Admin
  module CandidateBankDetails
    class ProofAccessService < ApplicationService
      ACCESS_TTL = ENV.fetch('ADMIN_DOCUMENT_ACCESS_TTL_SECONDS', 300).to_i.seconds

      def initialize(actor:, bank_detail:, request_id:)
        @actor = actor
        @bank_detail = bank_detail
        @request_id = request_id
      end

      def call
        raise BankProofAttachmentMissingError unless @bank_detail.proof.attached?

        expires_at = Time.current + ACCESS_TTL
        url = proof_url(expires_at:)
        create_audit_event!(expires_at:)

        AccessResult.new(bank_detail: @bank_detail, expires_at: expires_at.utc.iso8601, url:)
      end

      private

      def proof_url(expires_at:)
        Rails.application.routes.url_helpers.rails_service_blob_proxy_path(
          @bank_detail.proof.blob.signed_id(expires_at:),
          @bank_detail.proof.blob.filename,
          disposition: 'inline',
          only_path: true
        )
      end

      def create_audit_event!(expires_at:)
        AuditEvent.create!(
          **audit_event_attributes,
          metadata: audit_metadata(expires_at:),
          occurred_at: Time.current
        )
      end

      def candidate
        @candidate ||= @bank_detail.candidate_assignment.candidate
      end

      def audit_metadata(expires_at:)
        {
          actor_public_id: @actor.public_id,
          candidate_public_id: candidate.public_id,
          candidate_assignment_public_id: @bank_detail.candidate_assignment.public_id,
          bank_detail_public_id: @bank_detail.public_id,
          expires_at: expires_at.utc.iso8601
        }
      end

      def audit_event_attributes
        {
          actor: @actor,
          candidate: candidate,
          candidate_assignment: @bank_detail.candidate_assignment,
          entity_type: 'CandidateBankDetail',
          entity_id: @bank_detail.id,
          action_code: 'candidate_bank_proof_accessed',
          request_id: @request_id
        }
      end
    end
  end
end
