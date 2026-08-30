# frozen_string_literal: true

module Candidates
  module ApplicationProgress
    Summary = Data.define(
      :candidate_status,
      :current_workflow_stage,
      :documents,
      :workflow_timeline,
      :workflow_completed_count,
      :workflow_total_count,
      :workflow_progress_percentage,
      :workflow_updated_at
    )
  end
end
