# frozen_string_literal: true

module Admin
  module AuthenticationLogs
    # A staff account's recent authentication events (sign-ins, sign-outs,
    # session refreshes and rejected sign-ins), newest first.
    class StaffHistorySerializer
      def initialize(events)
        @events = events
      end

      def as_json(*)
        {
          events: @events.map do |event|
            {
              event_code: event.event_code,
              occurred_at: event.occurred_at,
              ip_address: event.ip_address,
              user_agent: event.user_agent
            }
          end
        }
      end
    end
  end
end
