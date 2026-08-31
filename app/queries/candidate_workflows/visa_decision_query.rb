# frozen_string_literal: true

module CandidateWorkflows
  class VisaDecisionQuery < ApplicationQuery
    def initialize(scope:)
      super()
      @scope = scope
    end

    def call
      @scope.includes(:recorded_by).order(:created_at)
    end
  end
end
