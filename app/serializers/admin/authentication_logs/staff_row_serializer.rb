# frozen_string_literal: true

module Admin
  module AuthenticationLogs
    # One Staff-tab row (a staff account loaded by StaffIndexQuery with its
    # sign-in aggregates).
    class StaffRowSerializer
      COPIED_ATTRIBUTES = %w[email role staff_state failed_attempts login_count last_login_at last_seen_at].freeze

      def initialize(row)
        @row = row
      end

      def as_json(*)
        { id: @row.public_id, locked: @row.locked_at.present? }
          .merge(@row.attributes.slice(*COPIED_ATTRIBUTES).symbolize_keys)
      end
    end
  end
end
