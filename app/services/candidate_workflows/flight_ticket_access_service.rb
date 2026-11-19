# frozen_string_literal: true

module CandidateWorkflows
  # Shared by both the staff and candidate ticket-access endpoints -- a
  # candidate downloading their own flight ticket and a staff member
  # downloading it go through the exact same short-lived signed-URL
  # mechanism and are both audited, distinguished only by whether `actor`
  # (always a staff User; nil for a candidate's own access, since
  # AuditEvent#actor is staff-only) is present. The candidate's boarding pass
  # photo (`attachment: :boarding_pass`) is served the same way.
  class FlightTicketAccessService < ApplicationService
    ACCESS_TTL = ENV.fetch('ADMIN_DOCUMENT_ACCESS_TTL_SECONDS', 300).to_i.seconds
    AUDIT_ACTION_CODES = {
      ticket: 'candidate_flight_ticket_accessed',
      boarding_pass: 'candidate_boarding_pass_accessed'
    }.freeze

    AccessResult = Data.define(:detail, :expires_at, :url)

    def initialize(actor:, candidate:, detail:, request_id:, attachment: :ticket)
      @actor = actor
      @candidate = candidate
      @detail = detail
      @request_id = request_id
      @attachment = attachment
    end

    def call
      raise DocumentAttachmentMissingError unless file.attached?

      expires_at = Time.current + ACCESS_TTL
      url = access_url(expires_at:)
      create_audit_event!(expires_at:)

      AccessResult.new(detail: @detail, expires_at: expires_at.utc.iso8601, url:)
    end

    private

    def file = @detail.public_send(@attachment)

    def access_url(expires_at:)
      Rails.application.routes.url_helpers.rails_service_blob_proxy_path(
        file.blob.signed_id(expires_at:),
        file.blob.filename,
        disposition: 'inline',
        only_path: true
      )
    end

    def create_audit_event!(expires_at:)
      AuditEvent.create!(audit_attributes(expires_at:))
    end

    def audit_attributes(expires_at:)
      {
        actor: @actor, candidate: @candidate, candidate_assignment: @detail.candidate_assignment,
        entity_type: 'CandidateFlightDetail', entity_id: @detail.id,
        action_code: AUDIT_ACTION_CODES.fetch(@attachment),
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
        candidate_assignment_public_id: @detail.candidate_assignment.public_id,
        flight_detail_public_id: @detail.public_id,
        expires_at: expires_at.utc.iso8601
      }.compact
    end
  end
end
