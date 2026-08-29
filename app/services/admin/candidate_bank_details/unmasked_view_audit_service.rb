# frozen_string_literal: true

module Admin
  module CandidateBankDetails
    class UnmaskedViewAuditService < ApplicationService
      def initialize(actor:, bank_detail:, request_id:)
        @actor = actor
        @bank_detail = bank_detail
        @request_id = request_id
      end

      def call
        AuditEvent.create!(
          **audit_event_attributes,
          metadata: audit_metadata,
          occurred_at: Time.current
        )
      end

      private

      def candidate
        @candidate ||= @bank_detail.candidate_assignment.candidate
      end

      def audit_metadata
        {
          actor_public_id: @actor.public_id,
          candidate_public_id: candidate.public_id,
          candidate_assignment_public_id: @bank_detail.candidate_assignment.public_id,
          bank_detail_public_id: @bank_detail.public_id
        }
      end

      def audit_event_attributes
        {
          actor: @actor,
          candidate: candidate,
          candidate_assignment: @bank_detail.candidate_assignment,
          entity_type: 'CandidateBankDetail',
          entity_id: @bank_detail.id,
          action_code: 'candidate_bank_detail_viewed_unmasked',
          request_id: @request_id
        }
      end
    end
  end
end
