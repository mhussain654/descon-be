# frozen_string_literal: true

module CandidateWorkflows
  # The `{code, name, position}` reference for either end of a stage-history
  # entry. `position` is the stage's place in the candidate's own process (from
  # the process-stage link, or the snapshot taken at transition time); the
  # name is the current localized catalog label.
  module HistoryStageReference
    module_function

    def from(history_entry)
      stage = history_entry.from_workflow_stage
      return if stage.blank?

      build(stage, history_entry.from_mobilization_process_stage&.position)
    end

    def to(history_entry)
      build(history_entry.to_workflow_stage,
            history_entry.to_mobilization_process_stage&.position || history_entry.position)
    end

    def build(stage, position)
      { code: stage.code, name: stage.name_for, position: }.compact
    end
  end
end
