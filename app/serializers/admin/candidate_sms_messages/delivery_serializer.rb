# frozen_string_literal: true

module Admin
  module CandidateSmsMessages
    # One SMS in a candidate's history: which message, in which language,
    # whether it went out, and who sent it (nil for an automatic one).
    class DeliverySerializer
      def initialize(delivery)
        @delivery = delivery
      end

      def as_json(*)
        {
          id: @delivery.public_id,
          message_code: @delivery.message_code,
          locale: @delivery.locale,
          status: @delivery.status,
          error_code: @delivery.error_code,
          sent_by: sent_by,
          created_at: @delivery.created_at.utc.iso8601,
          sent_at: @delivery.sent_at&.utc&.iso8601
        }
      end

      private

      def sent_by
        actor = @delivery.sent_by
        actor && { id: actor.public_id, role: actor.role }
      end
    end
  end
end
