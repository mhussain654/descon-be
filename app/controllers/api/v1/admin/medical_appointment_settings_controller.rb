# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff view and edit the default medical appointment (centre, address,
      # date, time) filled in when moving a candidate into a medical appointment
      # stage. Singleton show+update only.
      class MedicalAppointmentSettingsController < ProtectedStaffController
        AUDITED_ATTRIBUTES = %w[center_name center_address appointment_on appointment_time].freeze

        def show
          authorize ::MedicalAppointmentSetting, policy_class: ::Admin::MedicalAppointmentSettingPolicy

          render_success(data: serialized(::MedicalAppointmentSetting.current))
        end

        def update
          authorize ::MedicalAppointmentSetting, policy_class: ::Admin::MedicalAppointmentSettingPolicy

          render_success(data: serialized(update_setting!))
        end

        private

        def update_setting!
          ::MedicalAppointmentSetting.transaction do
            record = ::MedicalAppointmentSetting.lock.find(::MedicalAppointmentSetting.current.id)
            record.update!(update_params.merge(updated_by: current_user))
            record_audit!(record)
            record
          end
        end

        def update_params
          params.expect(medical_appointment_setting: AUDITED_ATTRIBUTES.map(&:to_sym))
        end

        def record_audit!(record)
          changes = record.saved_changes.slice(*AUDITED_ATTRIBUTES)
          return if changes.empty?

          ::AuditEvent.create!(
            actor: current_user, entity_type: 'MedicalAppointmentSetting', entity_id: record.id,
            action_code: 'medical_appointment_setting_updated', request_id: request.request_id,
            occurred_at: Time.current, metadata: { changes: changes }
          )
        end

        def serialized(record)
          ::Admin::MedicalAppointmentSettings::MedicalAppointmentSettingSerializer.new(record).as_json
        end
      end
    end
  end
end
