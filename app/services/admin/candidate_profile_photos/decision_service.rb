# frozen_string_literal: true

module Admin
  module CandidateProfilePhotos
    # Records a staff decision on a candidate's profile photo. Approved keeps
    # it. Rejected removes it (it must clearly show the candidate's own face)
    # and leaves the status "rejected", so the app tells the candidate to upload
    # a clear photo. Later an automatic face check can call this same service.
    class DecisionService < ApplicationService
      DECISIONS = %w[approved rejected].freeze

      def initialize(actor:, candidate:, decision:, request_id:)
        @actor = actor
        @candidate = candidate
        @decision = decision.to_s
        @request_id = request_id
      end

      def call
        raise ArgumentError, "unsupported decision: #{@decision}" unless DECISIONS.include?(@decision)

        ::Candidate.transaction do
          @candidate.lock!
          raise CandidateProfilePhotoNotFoundError unless @candidate.profile_photo.attached?

          @candidate.profile_photo.purge_later if rejected?
          @candidate.record_profile_photo_review!(@decision, reviewer: @actor)
          create_audit_event!
        end

        @candidate
      end

      private

      def rejected? = @decision == 'rejected'

      def create_audit_event!
        AuditEvent.create!(
          actor: @actor, candidate: @candidate, entity_type: 'Candidate', entity_id: @candidate.id,
          action_code: rejected? ? 'candidate_profile_photo_rejected' : 'candidate_profile_photo_approved',
          request_id: @request_id, occurred_at: @candidate.profile_photo_reviewed_at,
          metadata: { actor_public_id: @actor.public_id, candidate_public_id: @candidate.public_id }
        )
      end
    end
  end
end
