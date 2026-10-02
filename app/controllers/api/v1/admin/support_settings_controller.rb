# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff view and edit the singleton SupportSetting row -- the
      # helpline number candidates call from "Help & support". Singleton
      # show+update only, mirroring TrainingSettingsController.
      class SupportSettingsController < ProtectedStaffController
        def show
          authorize ::SupportSetting, policy_class: ::Admin::SupportSettingPolicy

          render_success(data: serialized(setting))
        end

        def update
          authorize ::SupportSetting, policy_class: ::Admin::SupportSettingPolicy

          render_success(data: serialized(update_setting!))
        end

        private

        def setting
          ::SupportSetting.current
        end

        def update_setting!
          ::SupportSetting.transaction do
            record = ::SupportSetting.lock.find(setting.id)
            record.update!(update_params.merge(updated_by: current_user))
            record_audit!(record)
            record
          end
        end

        def update_params
          params.expect(support_setting: [:phone_number])
        end

        def record_audit!(record)
          changes = record.saved_changes.slice('phone_number')
          return if changes.empty?

          ::AuditEvent.create!(
            actor: current_user, entity_type: 'SupportSetting', entity_id: record.id,
            action_code: 'support_setting_updated', request_id: request.request_id,
            occurred_at: Time.current, metadata: { changes: changes }
          )
        end

        def serialized(record)
          ::Admin::SupportSettings::SupportSettingSerializer.new(record).as_json
        end
      end
    end
  end
end
