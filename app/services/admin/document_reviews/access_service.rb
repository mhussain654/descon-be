# frozen_string_literal: true

module Admin
  module DocumentReviews
    class AccessService < ApplicationService
      ACCESS_TTL = ENV.fetch('ADMIN_DOCUMENT_ACCESS_TTL_SECONDS', 300).to_i.seconds

      def initialize(actor:, document:, request_id:)
        @actor = actor
        @document = document
        @request_id = request_id
      end

      def call
        raise DocumentAttachmentMissingError unless @document.file.attached?

        expires_at = Time.current + ACCESS_TTL
        url = access_url(expires_at:)
        create_audit_event!(expires_at:)

        AccessResult.new(
          document: @document,
          expires_at: expires_at.utc.iso8601,
          url:
        )
      end

      private

      def access_url(expires_at:)
        Rails.application.routes.url_helpers.rails_service_blob_proxy_path(
          @document.file.blob.signed_id(expires_at:),
          @document.file.blob.filename,
          disposition: 'inline',
          only_path: true
        )
      end

      def create_audit_event!(expires_at:)
        AuditEvent.create!(
          audit_attributes(expires_at:)
        )
      end

      def audit_attributes(expires_at:)
        {
          actor: @actor, candidate: candidate, candidate_assignment: @document.candidate_assignment,
          entity_type: 'CandidateDocument', entity_id: @document.id, action_code: 'candidate_document_accessed',
          request_id: @request_id,
          metadata: audit_metadata(expires_at:),
          occurred_at: Time.current
        }
      end

      def audit_metadata(expires_at:)
        {
          actor_public_id: @actor.public_id,
          candidate_public_id: candidate.public_id,
          candidate_assignment_public_id: @document.candidate_assignment.public_id,
          document_public_id: @document.public_id,
          requirement_code: @document.submission_item.requirement_code,
          expires_at: expires_at.utc.iso8601
        }
      end

      def candidate = @document.candidate_assignment.candidate
    end
  end
end
