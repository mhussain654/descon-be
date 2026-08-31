# frozen_string_literal: true

module Candidates
  module ApplicationProgress
    class Evaluator < ApplicationService
      def initialize(candidate:, assignment:, current_documents_by_type:, requirements:)
        @assignment = assignment
        @candidate = candidate
        @current_documents_by_type = current_documents_by_type
        @requirements = requirements
      end

      def call
        WorkflowSummaryBuilder.call(
          candidate: @candidate,
          assignment: @assignment,
          current_documents_by_type: @current_documents_by_type,
          requirements: @requirements
        )
      end
    end
  end
end
