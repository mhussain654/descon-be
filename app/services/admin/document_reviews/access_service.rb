# frozen_string_literal: true

module Admin
  module DocumentReviews
    class AccessService < ApplicationService
      ACCESS_TTL = ENV.fetch('ADMIN_DOCUMENT_ACCESS_TTL_SECONDS', 300).to_i.seconds

      # `file_id` picks one file of a multi-file document (defaults to its
      # representative file).
      def initialize(actor:, document:, request_id:, file_id: nil)
        @actor = actor
        @document = document
        @request_id = request_id
        @file_id = file_id
      end

      def call
        raise CandidateDocumentNotFoundError if document_file.blank?
        raise DocumentAttachmentMissingError unless document_file.file.attached?

        expires_at = Time.current + ACCESS_TTL
        url = access_url(expires_at:)
        create_audit_event!(expires_at:)

        AccessResult.new(document: @document, file: document_file, expires_at: expires_at.utc.iso8601, url:)
      end

      private

      def document_file
        @document_file ||= @document.file_for_access(@file_id)
      end

      def access_url(expires_at:)
        Rails.application.routes.url_helpers.rails_service_blob_proxy_path(
          document_file.file.blob.signed_id(expires_at:),
          document_file.file.blob.filename,
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
          file_public_id: document_file.public_id,
          requirement_code: @document.submission_item.requirement_code,
          expires_at: expires_at.utc.iso8601
        }
      end

      def candidate = @document.candidate_assignment.candidate
    end
  end
end
