# frozen_string_literal: true

module Admin
  module Communications
    # One row of the central cross-channel communications log. Reads only
    # preloaded associations (candidate_assignment.candidate, initiated_by)
    # -- never queries per-row -- so a paginated listing stays N+1 free.
    class CommunicationSerializer
      def initialize(communication)
        @communication = communication
      end

      def as_json(*)
        identity_attributes.merge(context_attributes).merge(timestamp_attributes)
      end

      private

      def identity_attributes
        {
          id: @communication.public_id,
          channel_code: @communication.channel_code,
          direction_code: @communication.direction_code,
          status_code: @communication.status_code,
          template_code: @communication.template_code,
          locale: @communication.locale
        }
      end

      def context_attributes
        {
          candidate_assignment: serialized_candidate_assignment,
          initiated_by: serialized_initiated_by,
          recipient_masked: @communication.recipient_masked,
          provider_reference: @communication.provider_reference,
          error_code: @communication.error_code
        }
      end

      def timestamp_attributes
        {
          sent_at: @communication.sent_at&.utc&.iso8601,
          delivered_at: @communication.delivered_at&.utc&.iso8601,
          failed_at: @communication.failed_at&.utc&.iso8601,
          created_at: @communication.created_at.utc.iso8601
        }
      end

      def serialized_candidate_assignment
        assignment = @communication.candidate_assignment
        return nil if assignment.blank?

        {
          id: assignment.public_id,
          reference_number: assignment.reference_number,
          candidate_id: assignment.candidate.public_id
        }
      end

      def serialized_initiated_by
        actor = @communication.initiated_by
        return nil if actor.blank?

        { id: actor.public_id, role: actor.role }
      end
    end
  end
end
