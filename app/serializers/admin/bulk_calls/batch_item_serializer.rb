# frozen_string_literal: true

module Admin
  module BulkCalls
    # One candidate's row in a batch: what happened to their call, and (once
    # placed) how the call itself turned out.
    class BatchItemSerializer
      def initialize(item)
        @item = item
      end

      def as_json(*)
        {
          id: @item.id,
          candidate: { id: @item.candidate.public_id, full_name: @item.candidate.full_name,
                       mobile_number_masked: PhoneNumbers::Masker.call(@item.candidate.mobile_number) },
          status: @item.status,
          skip_reason: @item.skip_reason,
          call: serialized_call
        }
      end

      private

      def serialized_call
        call = @item.candidate_ai_call
        return nil if call.blank?

        { id: call.public_id, status: call.status, outcome: call.outcome, outcome_reason: call.outcome_reason,
          callback_requested_at: call.callback_requested_at&.utc&.iso8601 }
      end
    end
  end
end
