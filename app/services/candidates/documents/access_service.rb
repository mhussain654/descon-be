# frozen_string_literal: true

module Candidates
  module Documents
    # Lets a candidate retrieve a short-lived signed URL for their own
    # already-uploaded document, so they can always see what they submitted
    # -- mirrors CandidateWorkflows::VisaCopyAccessService/
    # FlightTicketAccessService exactly (same TTL env var, same
    # rails_service_blob_proxy_path mechanism, same audit shape), and reuses
    # the `candidate_document_accessed` action code Admin::DocumentReviews::
    # AccessService already writes for a staff member viewing the same file,
    # distinguished only by `actor` being nil here.
    class AccessService < ApplicationService
      ACCESS_TTL = ENV.fetch('ADMIN_DOCUMENT_ACCESS_TTL_SECONDS', 300).to_i.seconds
      DISPOSITIONS = %w[inline attachment].freeze

      AccessResult = Data.define(:document, :file, :expires_at, :url)

      # `file_id` picks one file of a multi-file document (defaults to its
      # representative file).
      # rubocop:disable Metrics/ParameterLists
      def initialize(actor:, candidate:, document:, request_id:, disposition: 'inline', file_id: nil)
        # rubocop:enable Metrics/ParameterLists
        @actor = actor
        @candidate = candidate
        @document = document
        @request_id = request_id
        @disposition = disposition
        @file_id = file_id
      end

      def call
        raise NotFoundError if document_file.blank?
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
          disposition: @disposition,
          only_path: true
        )
      end

      def create_audit_event!(expires_at:)
        AuditEvent.create!(audit_attributes(expires_at:))
      end

      def audit_attributes(expires_at:)
        {
          actor: @actor, candidate: @candidate, candidate_assignment: @document.candidate_assignment,
          entity_type: 'CandidateDocument', entity_id: @document.id,
          action_code: 'candidate_document_accessed',
          request_id: @request_id,
          metadata: audit_metadata(expires_at:),
          occurred_at: Time.current
        }
      end

      def audit_metadata(expires_at:)
        {
          actor_public_id: @actor&.public_id,
          accessed_by: @actor.present? ? 'staff' : 'candidate',
          candidate_public_id: @candidate.public_id,
          candidate_assignment_public_id: @document.candidate_assignment.public_id,
          disposition: @disposition,
          expires_at: expires_at.utc.iso8601
        }.merge(document_audit_metadata).compact
      end

      def document_audit_metadata
        {
          document_public_id: @document.public_id,
          file_public_id: document_file.public_id,
          requirement_code: @document.submission_item&.requirement_code
        }
      end
    end
  end
end
