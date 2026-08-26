# frozen_string_literal: true

module Candidates
  module Documents
    class RequirementResolver < ApplicationService
      def initialize(candidate:)
        @candidate = candidate
      end

      def call
        return [] if current_assignment.blank?

        applicable_requirements
          .group_by(&:document_type_id)
          .values
          .map { |requirements| prioritize(requirements) }
          .sort_by { |requirement| requirement.document_type.code }
      end

      private

      def current_assignment
        @current_assignment ||= @candidate.current_assignment
      end

      def applicable_requirements
        DocumentRequirement
          .includes(:document_type)
          .where(active: true)
          .where(country_id: [nil, current_assignment.country_id])
          .where(project_id: [nil, current_assignment.project_id])
          .where(craft_id: [nil, current_assignment.craft_id])
      end

      def prioritize(requirements)
        requirements.max_by do |requirement|
          [specificity_score(requirement), required_priority(requirement), -requirement.id]
        end
      end

      def specificity_score(requirement)
        [requirement.country_id, requirement.project_id, requirement.craft_id].count(&:present?)
      end

      def required_priority(requirement)
        requirement.required ? 1 : 0
      end
    end
  end
end
