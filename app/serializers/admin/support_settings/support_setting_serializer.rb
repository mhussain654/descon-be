# frozen_string_literal: true

module Admin
  module SupportSettings
    class SupportSettingSerializer
      def initialize(setting)
        @setting = setting
      end

      def as_json(*)
        {
          phone_number: @setting.phone_number,
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
