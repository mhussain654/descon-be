# frozen_string_literal: true

module Admin
  module Candidates
    # Records the administrative act of creating or editing a candidate's
    # profile (AGENTS.md: "Record security-sensitive and administrative
    # actions in an audit trail"), same shape as
    # CandidateWorkflows::VisaDecisionAuditRecorder.
    class AuditRecorder < ApplicationService
      def initialize(actor:, candidate:, action_code:, changed_fields:)
        @actor = actor
        @candidate = candidate
        @action_code = action_code
        @changed_fields = changed_fields
      end

      def call = AuditEvent.create!(audit_event_attributes)

      private

      def assignment = @candidate.current_assignment

      def audit_metadata
        {
          candidate_public_id: @candidate.public_id,
          candidate_assignment_public_id: assignment&.public_id,
          changed_fields: @changed_fields
        }.compact
      end

      def audit_event_attributes
        {
          actor: @actor,
          candidate: @candidate,
          candidate_assignment: assignment,
          entity_type: 'Candidate',
          entity_id: @candidate.id,
          action_code: @action_code,
          metadata: audit_metadata,
          occurred_at: Time.current
        }
      end
    end
  end
end
