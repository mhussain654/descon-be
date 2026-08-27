# frozen_string_literal: true

module Candidates
  module ApplicationProgress
    Summary = Data.define(:candidate_status, :current_workflow_stage, :documents)
  end
end
