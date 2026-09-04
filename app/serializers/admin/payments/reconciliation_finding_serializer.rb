# frozen_string_literal: true

module Admin
  module Payments
    class ReconciliationFindingSerializer
      def initialize(finding)
        @finding = finding
      end

      def as_json(*)
        {
          id: @finding.public_id,
          finding_code: @finding.finding_code,
          state: @finding.state_code,
          resolved_at: @finding.resolved_at&.utc&.iso8601,
          resolved_by: serialized_resolved_by,
          resolution_note: @finding.resolution_note,
          created_at: @finding.created_at.utc.iso8601
        }.compact
      end

      private

      def serialized_resolved_by
        resolver = @finding.resolved_by
        return nil if resolver.blank?

        { id: resolver.public_id, role: resolver.role }
      end
    end
  end
end
