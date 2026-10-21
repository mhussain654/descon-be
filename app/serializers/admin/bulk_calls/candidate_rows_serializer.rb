# frozen_string_literal: true

module Admin
  module BulkCalls
    # The candidates shown on the bulk-call page, each with whether they were
    # already called with the chosen voice. The calls and queued batch items for
    # the whole page are loaded in two queries, not one per candidate.
    class CandidateRowsSerializer
      def initialize(candidates, voice:)
        @candidates = candidates.to_a
        @voice = voice
      end

      def as_json(*)
        @candidates.map { |candidate| row(candidate) }
      end

      private

      def row(candidate)
        assignment = candidate.current_assignment
        last_call = calls_by_assignment[assignment&.id]&.first
        {
          id: candidate.public_id,
          full_name: candidate.full_name,
          reference_number: assignment&.reference_number,
          mobile_number_masked: PhoneNumbers::Masker.call(candidate.mobile_number),
          call_state: call_state(assignment, last_call),
          last_call: serialized_call(last_call)
        }
      end

      def call_state(assignment, last_call)
        return 'called' if last_call.present?

        queued_assignment_ids.include?(assignment&.id) ? 'queued' : 'not_called'
      end

      def serialized_call(call)
        return nil if call.blank?

        { status: call.status, outcome: call.outcome, outcome_reason: call.outcome_reason,
          called_at: call.created_at.utc.iso8601 }
      end

      def assignment_ids = @assignment_ids ||= @candidates.filter_map { |candidate| candidate.current_assignment&.id }

      def calls_by_assignment
        @calls_by_assignment ||= CandidateAiCall.where(candidate_assignment_id: assignment_ids,
                                                       provider_voice_id: @voice.voice_id)
                                                .order(created_at: :desc).group_by(&:candidate_assignment_id)
      end

      def queued_assignment_ids
        @queued_assignment_ids ||= BulkCallBatchItem.queued.joins(:bulk_call_batch)
                                                    .where(candidate_assignment_id: assignment_ids,
                                                           bulk_call_batches: { provider_voice_id: @voice.voice_id })
                                                    .pluck(:candidate_assignment_id)
      end
    end
  end
end
