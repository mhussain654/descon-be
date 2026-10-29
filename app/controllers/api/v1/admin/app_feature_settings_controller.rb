# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets an admin view and change the App Settings feature switches (the
      # singleton AppFeatureSetting row). Every change is audited.
      class AppFeatureSettingsController < ProtectedStaffController
        SWITCH_PARAMS = AppFeatureSetting::SWITCHES.map { |switch| :"#{switch}_enabled" }.freeze
        AUDITED_FIELDS = (SWITCH_PARAMS.map(&:to_s) + ['disabled_sms_messages']).freeze

        def show
          authorize ::AppFeatureSetting, policy_class: ::Admin::AppFeatureSettingPolicy

          render_success(data: serialized(setting))
        end

        def update
          authorize ::AppFeatureSetting, policy_class: ::Admin::AppFeatureSettingPolicy

          render_success(data: serialized(update_setting!))
        end

        private

        def setting
          ::AppFeatureSetting.current
        end

        def update_setting!
          ::AppFeatureSetting.transaction do
            record = ::AppFeatureSetting.lock.find(setting.id)
            record.update!(update_params.merge(updated_by: current_user))
            record_audit!(record)
            record
          end
        end

        def update_params
          params.expect(app_feature_setting: [*SWITCH_PARAMS, { disabled_sms_messages: [] }])
        end

        def record_audit!(record)
          changes = record.saved_changes.slice(*AUDITED_FIELDS)
          return if changes.empty?

          ::AuditEvent.create!(
            actor: current_user, entity_type: 'AppFeatureSetting', entity_id: record.id,
            action_code: 'app_feature_setting_updated', request_id: request.request_id,
            occurred_at: Time.current, metadata: { changes: }
          )
        end

        def serialized(record)
          ::Admin::AppFeatureSettings::AppFeatureSettingSerializer.new(record).as_json
        end
      end
    end
  end
end
