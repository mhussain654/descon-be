# frozen_string_literal: true

module Candidates
  module ProfilePhotos
    # Removes the candidate's own profile photo (a no-op when none is set) and
    # records an audit event when something was actually removed.
    class RemoveService < ApplicationService
      def initialize(candidate:, request_id:)
        @candidate = candidate
        @request_id = request_id
      end

      def call
        return @candidate unless @candidate.profile_photo.attached?

        ::Candidate.transaction do
          @candidate.profile_photo.purge_later
          @candidate.record_profile_photo_review!(nil)
          create_audit_event!
        end

        @candidate
      end

      private

      def create_audit_event!
        AuditEvent.create!(
          actor: nil, candidate: @candidate, entity_type: 'Candidate', entity_id: @candidate.id,
          action_code: 'candidate_profile_photo_removed', request_id: @request_id,
          metadata: { candidate_public_id: @candidate.public_id }, occurred_at: Time.current
        )
      end
    end
  end
end
