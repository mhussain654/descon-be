# frozen_string_literal: true

module CandidateWorkflows
  # Shared by both the staff and candidate visa-copy-access endpoints --
  # mirrors FlightTicketAccessService exactly: a candidate downloading their
  # own visa copy and a staff member downloading it go through the same
  # short-lived signed-URL mechanism and are both audited, distinguished only
  # by whether `actor` (always a staff User; nil for a candidate's own
  # access, since AuditEvent#actor is staff-only) is present.
  class VisaCopyAccessService < ApplicationService
    ACCESS_TTL = ENV.fetch('ADMIN_DOCUMENT_ACCESS_TTL_SECONDS', 300).to_i.seconds

    AccessResult = Data.define(:decision, :expires_at, :url)

    def initialize(actor:, candidate:, decision:, request_id:)
      @actor = actor
      @candidate = candidate
      @decision = decision
      @request_id = request_id
    end

    def call
      raise DocumentAttachmentMissingError unless @decision.visa_copy.attached?

      expires_at = Time.current + ACCESS_TTL
      url = access_url(expires_at:)
      create_audit_event!(expires_at:)

      AccessResult.new(decision: @decision, expires_at: expires_at.utc.iso8601, url:)
    end

    private

    def access_url(expires_at:)
      Rails.application.routes.url_helpers.rails_service_blob_proxy_path(
        @decision.visa_copy.blob.signed_id(expires_at:),
        @decision.visa_copy.blob.filename,
        disposition: 'inline',
        only_path: true
      )
    end

    def create_audit_event!(expires_at:)
      AuditEvent.create!(audit_attributes(expires_at:))
    end

    def audit_attributes(expires_at:)
      {
        actor: @actor, candidate: @candidate, candidate_assignment: @decision.candidate_assignment,
        entity_type: 'CandidateVisaDecision', entity_id: @decision.id,
        action_code: 'candidate_visa_decision_accessed',
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
        candidate_assignment_public_id: @decision.candidate_assignment.public_id,
        visa_decision_public_id: @decision.public_id,
        expires_at: expires_at.utc.iso8601
      }.compact
    end
  end
end
