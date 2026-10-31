# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets a developer view and edit each send.pk message's template ids and
      # on/off switch (SmsTemplate). Index+update only: the messages are fixed
      # in code, so rows are edited, never added or removed. Every change is
      # audited.
      class SmsTemplatesController < ProtectedStaffController
        UPDATE_PARAMS = %i[template_id_en template_id_ur enabled].freeze
        AUDITED_FIELDS = UPDATE_PARAMS.map(&:to_s).freeze

        def index
          authorize ::SmsTemplate, policy_class: ::Admin::SmsTemplatePolicy

          render_success(data: ordered_templates.map { |template| serialized(template) })
        end

        def update
          authorize ::SmsTemplate, policy_class: ::Admin::SmsTemplatePolicy

          render_success(data: serialized(update_template!))
        end

        private

        # Listed in the order the messages reach a candidate.
        def ordered_templates
          template_scope.includes(:updated_by).sort_by { |template| ::SmsTemplate::MESSAGE_CODES.index(template.message_code) }
        end

        def template_scope
          policy_scope(::SmsTemplate, policy_scope_class: ::Admin::SmsTemplatePolicy::Scope)
        end

        def update_template!
          ::SmsTemplate.transaction do
            record = template_scope.lock.find_by!(message_code: params.expect(:message_code))
            record.update!(update_params.merge(updated_by: current_user))
            record_audit!(record)
            record
          end
        end

        def update_params
          params.expect(sms_template: UPDATE_PARAMS)
        end

        def record_audit!(record)
          changes = record.saved_changes.slice(*AUDITED_FIELDS)
          return if changes.empty?

          ::AuditEvent.create!(
            actor: current_user, entity_type: 'SmsTemplate', entity_id: record.id,
            action_code: 'sms_template_updated', request_id: request.request_id,
            occurred_at: Time.current, metadata: { message_code: record.message_code, changes: }
          )
        end

        def serialized(record)
          ::Admin::SmsTemplates::SmsTemplateSerializer.new(record).as_json
        end
      end
    end
  end
end
