# frozen_string_literal: true

module CandidateWorkflows
  # The `{code, name, position}` reference for either end of a stage-history
  # entry, served from the entry's immutable snapshot -- exactly what the stage
  # was called and where it sat in the candidate's process when the transition
  # happened, never today's catalog label.
  module HistoryStageReference
    module_function

    def from(history_entry) = history_entry.snapshot_stage(:from)

    def to(history_entry) = history_entry.snapshot_stage(:to)
  end
end
