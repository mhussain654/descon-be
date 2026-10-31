# frozen_string_literal: true

module Admin
  module SmsTemplates
    # One send.pk message with the values its template must use and whether it
    # may be switched off (the OTP never can).
    class SmsTemplateSerializer
      def initialize(template)
        @template = template
      end

      def as_json(*)
        {
          message_code: @template.message_code,
          template_id_en: @template.template_id_en,
          template_id_ur: @template.template_id_ur,
          enabled: @template.enabled,
          can_disable: !@template.always_enabled?,
          variables: @template.variables,
          updated_by: serialized_updated_by,
          updated_at: @template.updated_at.utc.iso8601
        }
      end

      private

      def serialized_updated_by
        actor = @template.updated_by
        return nil if actor.blank?

        { id: actor.public_id, role: actor.role }
      end
    end
  end
end
