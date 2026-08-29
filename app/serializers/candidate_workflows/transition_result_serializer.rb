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
        from_stage: history_entry.from_workflow_stage && stage_reference(history_entry.from_workflow_stage),
        to_stage: stage_reference(history_entry.to_workflow_stage),
        occurred_at: history_entry.occurred_at.utc.iso8601,
        reason_code: history_entry.reason_code,
        details: history_entry.metadata.presence
      }.compact
    end

    def stage_reference(stage)
      {
        code: stage.code,
        name: stage.name_for,
        position: stage.position
      }
    end
  end
end
