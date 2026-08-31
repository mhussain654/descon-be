# frozen_string_literal: true

module CandidateWorkflows
  class QvcAttemptQuery < ApplicationQuery
    def initialize(scope:, no_show_only: false)
      super()
      @scope = scope
      @no_show_only = no_show_only
    end

    def call
      relation = @scope.includes(:scheduled_by, :outcome_recorded_by)
      relation = relation.no_shows if @no_show_only
      relation.ordered
    end
  end
end
