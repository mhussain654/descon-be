# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff view and edit the singleton TrainingSetting row -- the one
      # external link candidates are sent to for training documents/videos.
      # Singleton show+update only: no create/destroy route, since the row
      # is never manually created (TrainingSetting.current seeds it lazily).
      class TrainingSettingsController < ProtectedStaffController
        def show
          authorize ::TrainingSetting, policy_class: ::Admin::TrainingSettingPolicy

          render_success(data: serialized(setting))
        end

        def update
          authorize ::TrainingSetting, policy_class: ::Admin::TrainingSettingPolicy

          render_success(data: serialized(update_setting!))
        end

        private

        def setting
          ::TrainingSetting.current
        end

        def update_setting!
          ::TrainingSetting.transaction do
            record = ::TrainingSetting.lock.find(setting.id)
            record.update!(update_params.merge(updated_by: current_user))
            record_audit!(record)
            record
          end
        end

        def update_params
          params.expect(training_setting: [:url])
        end

        def record_audit!(record)
          changes = record.saved_changes.slice('url')
          return if changes.empty?

          ::AuditEvent.create!(
            actor: current_user, entity_type: 'TrainingSetting', entity_id: record.id,
            action_code: 'training_setting_updated', request_id: request.request_id,
            occurred_at: Time.current, metadata: { changes: changes }
          )
        end

        def serialized(record)
          ::Admin::TrainingSettings::TrainingSettingSerializer.new(record).as_json
        end
      end
    end
  end
end
