# frozen_string_literal: true

module Candidates
  module DocumentSubmissions
    class ProgressSummaryBuilder < ApplicationService
      def initialize(candidate:, assignment:, current_documents_by_type:, requirements:)
        @candidate = candidate
        @assignment = assignment
        @current_documents_by_type = current_documents_by_type
        @requirements = requirements
      end

      def call
        Candidates::ApplicationProgress::SummaryService.call(
          candidate: @candidate,
          assignment: @assignment,
          current_documents_by_type: @current_documents_by_type,
          requirements: @requirements
        )
      end
    end
  end
end
