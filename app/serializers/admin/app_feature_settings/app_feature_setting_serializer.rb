# frozen_string_literal: true

module Admin
  module AppFeatureSettings
    # Each switch with whether the server is set up for it (`server_ready`): a
    # feature runs only when both are on, so the admin page can say why a switch
    # that is on still does nothing.
    class AppFeatureSettingSerializer
      def initialize(setting, server_readiness: ServerReadiness.new)
        @setting = setting
        @server_readiness = server_readiness
      end

      def as_json(*)
        switches.merge(
          sms_messages:,
          server_ready: @server_readiness.as_json,
          updated_by: serialized_updated_by,
          updated_at: @setting.updated_at.utc.iso8601
        )
      end

      private

      def switches
        AppFeatureSetting::SWITCHES.to_h { |switch| [:"#{switch}_enabled", @setting.public_send(:"#{switch}_enabled")] }
      end

      def sms_messages
        CandidateSmsDelivery::MESSAGE_CODES.map do |code|
          { code:, enabled: @setting.disabled_sms_messages.exclude?(code),
            template_ready: @server_readiness.sms_template_ready?(code) }
        end
      end

      def serialized_updated_by
        actor = @setting.updated_by
        return nil if actor.blank?

        { id: actor.public_id, role: actor.role }
      end
    end
  end
end
