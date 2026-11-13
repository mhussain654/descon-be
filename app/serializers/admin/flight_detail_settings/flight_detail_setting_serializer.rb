# frozen_string_literal: true

module Admin
  module FlightDetailSettings
    class FlightDetailSettingSerializer
      def initialize(setting)
        @setting = setting
      end

      def as_json(*)
        {
          airline: @setting.airline,
          flight_number: @setting.flight_number,
          sector: @setting.sector,
          departure_on: @setting.departure_on&.iso8601,
          departure_time: @setting.departure_time,
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
