# frozen_string_literal: true

module Candidates
  module Documents
    # The candidate's document checklist configuration, decided entirely by the
    # backend from their current assignment: for each document type the most
    # specific active row wins --
    #
    #   country + project + craft > country + project > country + craft > country > common
    #
    # (rows scoped by project and/or craft without a country rank below a
    # country row). A winning `not_applicable` row drops the document; rows
    # marked `driver_only` are considered only when the assignment's craft is a
    # driver craft. The result is ordered by `display_position`.
    class RequirementResolver < ApplicationService
      SCOPE_WEIGHTS = { country_id: 4, project_id: 2, craft_id: 1 }.freeze

      def initialize(candidate:, assignment: nil)
        @candidate = candidate
        @assignment = assignment
      end

      def call
        return [] if current_assignment.blank?

        applicable_requirements
          .group_by(&:document_type_id)
          .values
          .map { |requirements| requirements.max_by { |requirement| [specificity(requirement), -requirement.id] } }
          .reject(&:not_applicable?)
          .sort_by { |requirement| [requirement.display_position, requirement.document_type.code] }
      end

      private

      def current_assignment
        @current_assignment ||= @assignment || @candidate.current_assignment
      end

      def applicable_requirements
        # `document_types.active` also has to be filtered here, not just
        # `document_requirements.active` -- retiring a document type
        # (marking it inactive) is otherwise silently ignored: the
        # requirement row linking to it can stay active, so the retired
        # type keeps appearing in candidate checklists and the HR review
        # queue.
        scope = DocumentRequirement
                .includes(:document_type)
                .where(active: true)
                .where(document_types: { active: true })
                .where(country_id: [nil, current_assignment.country_id])
                .where(project_id: [nil, current_assignment.project_id])
                .where(craft_id: [nil, current_assignment.craft_id])
        driver_craft? ? scope : scope.where(driver_only: false)
      end

      def driver_craft?
        Craft.exists?(id: current_assignment.craft_id, is_driver: true)
      end

      def specificity(requirement)
        SCOPE_WEIGHTS.sum { |column, weight| requirement.public_send(column).present? ? weight : 0 }
      end
    end
  end
end
