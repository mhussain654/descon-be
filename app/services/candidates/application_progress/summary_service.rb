# frozen_string_literal: true

module Candidates
  module ApplicationProgress
    class SummaryService < ApplicationService
      def initialize(candidate:, assignment: nil, current_documents_by_type: nil, requirements: nil)
        @assignment = assignment
        @candidate = candidate
        @current_documents_by_type = current_documents_by_type
        @requirements = requirements
      end

      def call
        Evaluator.call(
          candidate: @candidate,
          assignment: current_assignment,
          current_documents_by_type:,
          requirements:
        )
      end

      private

      def current_assignment
        @current_assignment ||= @assignment || @candidate.current_assignment
      end

      def current_documents_by_type
        @current_documents_by_type ||= load_current_documents_by_type
      end

      def requirements
        @requirements ||= Candidates::Documents::RequirementResolver.call(
          candidate: @candidate,
          assignment: current_assignment
        )
      end

      def load_current_documents_by_type
        return {} if current_assignment.blank?

        current_assignment
          .candidate_documents
          .current_version
          .where(document_type_id: requirements.map(&:document_type_id))
          .index_by(&:document_type_id)
      end
    end
  end
end
