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
          AuditEvent.create!(
            actor: nil, candidate: @candidate, entity_type: 'Candidate', entity_id: @candidate.id,
            action_code: 'candidate_profile_photo_removed', request_id: @request_id,
            metadata: { candidate_public_id: @candidate.public_id }, occurred_at: Time.current
          )
        end

        @candidate
      end
    end
  end
end
