# frozen_string_literal: true

module Admin
  module Reports
    # Docs -> Verified -> Mobilized conversion funnel (MPS-806). A
    # candidate's current stage only ever advances forward (each
    # destination stage is recorded at most once per assignment -- see the
    # unique index on candidate_stage_histories), so "reached at least
    # stage X" is reliably `current stage position >= X's position`; no
    # separate historical scan is needed for a simple funnel count.
    class ConversionQuery < ApplicationQuery
      FUNNEL_STAGE_CODES = %w[documents_uploaded verified mobilized].freeze

      def initialize(scope: Candidate.all)
        super()
        @scope = scope
      end

      def call
        total = total_count
        FUNNEL_STAGE_CODES.map do |code|
          reached = reached_count(position_for(code))
          { code:, count: reached, percentage: percentage(reached, total) }
        end
      end

      private

      def base_scope
        @base_scope ||= CurrentAssignmentJoin.call(scope: @scope)
      end

      def total_count
        @total_count ||= base_scope.count
      end

      def reached_count(position)
        base_scope.where(current_assignments: { current_workflow_stage_id: stage_ids_at_or_after(position) }).count
      end

      def stage_ids_at_or_after(position)
        stages_by_position.select { |stage_position, _id| stage_position >= position }.values
      end

      def stages_by_position
        @stages_by_position ||= WorkflowStage.pluck(:position, :id).to_h
      end

      def position_for(code)
        WorkflowStage::CANONICAL_STAGES.find { |stage| stage.fetch(:code) == code }.fetch(:position)
      end

      def percentage(count, total)
        return 0.0 if total.zero?

        (count.to_f / total * 100).round(1)
      end
    end
  end
end
