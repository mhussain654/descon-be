# frozen_string_literal: true

module CandidateWorkflows
  class TransitionResultSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        workflow: StateSerializer.new(@result.fetch(:snapshot)).as_json,
        transition: serialized_transition(@result.fetch(:history_entry))
      }
    end

    private

    def serialized_transition(history_entry)
      {
        from_stage: HistoryStageReference.from(history_entry),
        to_stage: HistoryStageReference.to(history_entry),
        occurred_at: history_entry.occurred_at.utc.iso8601,
        reason_code: history_entry.reason_code,
        details: history_entry.metadata.presence
      }.compact
    end
  end
end
