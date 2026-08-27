# frozen_string_literal: true

module Candidates
  module ApplicationProgress
    DocumentsSummary = Data.define(
      :blocking_requirements,
      :can_submit,
      :completion_percentage,
      :missing,
      :pending_review,
      :rejected,
      :required_total,
      :submission_state,
      :submitted_total,
      :uploaded,
      :verified
    )
  end
end
