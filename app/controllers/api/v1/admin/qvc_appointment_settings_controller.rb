# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff view and edit the default QVC appointment (centre, address,
      # date, time) filled in when booking a candidate's QVC appointment.
      # Singleton show+update only.
      class QvcAppointmentSettingsController < ProtectedStaffController
        AUDITED_ATTRIBUTES = %w[center_name center_address appointment_on appointment_time].freeze

        def show
          authorize ::QvcAppointmentSetting, policy_class: ::Admin::QvcAppointmentSettingPolicy

          render_success(data: serialized(::QvcAppointmentSetting.current))
        end

        def update
          authorize ::QvcAppointmentSetting, policy_class: ::Admin::QvcAppointmentSettingPolicy

          render_success(data: serialized(update_setting!))
        end

        private

        def update_setting!
          ::QvcAppointmentSetting.transaction do
            record = ::QvcAppointmentSetting.lock.find(::QvcAppointmentSetting.current.id)
            record.update!(update_params.merge(updated_by: current_user))
            record_audit!(record)
            record
          end
        end

        def update_params
          params.expect(qvc_appointment_setting: AUDITED_ATTRIBUTES.map(&:to_sym))
        end

        def record_audit!(record)
          changes = record.saved_changes.slice(*AUDITED_ATTRIBUTES)
          return if changes.empty?

          ::AuditEvent.create!(
            actor: current_user, entity_type: 'QvcAppointmentSetting', entity_id: record.id,
            action_code: 'qvc_appointment_setting_updated', request_id: request.request_id,
            occurred_at: Time.current, metadata: { changes: changes }
          )
        end

        def serialized(record)
          ::Admin::QvcAppointmentSettings::QvcAppointmentSettingSerializer.new(record).as_json
        end
      end
    end
  end
end
