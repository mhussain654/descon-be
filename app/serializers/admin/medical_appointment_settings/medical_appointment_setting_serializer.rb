# frozen_string_literal: true

module Admin
  module MedicalAppointmentSettings
    class MedicalAppointmentSettingSerializer
      def initialize(setting)
        @setting = setting
      end

      def as_json(*)
        {
          center_name: @setting.center_name,
          center_address: @setting.center_address,
          appointment_on: @setting.appointment_on&.iso8601,
          appointment_time: @setting.appointment_time,
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
