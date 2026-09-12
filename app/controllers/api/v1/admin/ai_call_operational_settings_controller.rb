# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff view and edit the singleton AiCallOperationalSetting row
      # -- the 5 DB-editable overrides for AiCalls::Configuration's
      # otherwise ENV-only rate-limit/calling-hours knobs. Singleton show+
      # update only: no create/destroy route, since the row is never
      # manually created (AiCallOperationalSetting.current seeds it lazily).
      class AiCallOperationalSettingsController < ProtectedStaffController
        UPDATE_PARAMS = %i[
          outbound_trigger_cooldown_minutes daily_outbound_call_limit admin_trigger_rate_limit_per_hour
          calling_hours_start calling_hours_end max_call_duration_minutes
        ].freeze

        def show
          authorize ::AiCallOperationalSetting, policy_class: ::Admin::AiCallOperationalSettingPolicy

          render_success(data: serialized(setting))
        end

        def update
          authorize ::AiCallOperationalSetting, policy_class: ::Admin::AiCallOperationalSettingPolicy

          render_success(data: serialized(update_setting!))
        end

        private

        def setting
          ::AiCallOperationalSetting.current
        end

        def update_setting!
          ::AiCallOperationalSetting.transaction do
            record = ::AiCallOperationalSetting.lock.find(setting.id)
            record.update!(update_params.merge(updated_by: current_user))
            record_audit!(record)
            record
          end
        end

        def update_params
          params.expect(ai_call_operational_setting: UPDATE_PARAMS)
        end

        def record_audit!(record)
          changes = record.saved_changes.slice(*UPDATE_PARAMS.map(&:to_s))
          return if changes.empty?

          ::AuditEvent.create!(
            actor: current_user, entity_type: 'AiCallOperationalSetting', entity_id: record.id,
            action_code: 'ai_call_operational_setting_updated', request_id: request.request_id,
            occurred_at: Time.current, metadata: { changes: changes }
          )
        end

        def serialized(record)
          ::Admin::AiCallOperationalSettings::AiCallOperationalSettingSerializer.new(record).as_json
        end
      end
    end
  end
end
