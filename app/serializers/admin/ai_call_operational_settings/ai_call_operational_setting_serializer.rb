# frozen_string_literal: true

module Admin
  module AiCallOperationalSettings
    class AiCallOperationalSettingSerializer
      def initialize(setting)
        @setting = setting
      end

      def as_json(*)
        {
          outbound_trigger_cooldown_minutes: @setting.outbound_trigger_cooldown_minutes,
          daily_outbound_call_limit: @setting.daily_outbound_call_limit,
          admin_trigger_rate_limit_per_hour: @setting.admin_trigger_rate_limit_per_hour,
          calling_hours_start: @setting.calling_hours_start,
          calling_hours_end: @setting.calling_hours_end,
          max_call_duration_minutes: @setting.max_call_duration_minutes,
          updated_by: serialized_updated_by,
          updated_at: @setting.updated_at.utc.iso8601
        }
      end

      private

      def serialized_updated_by
        actor = @setting.updated_by
        return nil if actor.blank?

        { id: actor.public_id, role: actor.role }
      end
    end
  end
end
