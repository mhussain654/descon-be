# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff view and edit the default flight details (airline, flight
      # number, sector, departure date and time) filled in when adding a
      # candidate's flight details. Singleton show+update only.
      class FlightDetailSettingsController < ProtectedStaffController
        AUDITED_ATTRIBUTES = %w[airline flight_number sector departure_on departure_time].freeze

        def show
          authorize ::FlightDetailSetting, policy_class: ::Admin::FlightDetailSettingPolicy

          render_success(data: serialized(::FlightDetailSetting.current))
        end

        def update
          authorize ::FlightDetailSetting, policy_class: ::Admin::FlightDetailSettingPolicy

          render_success(data: serialized(update_setting!))
        end

        private

        def update_setting!
          ::FlightDetailSetting.transaction do
            record = ::FlightDetailSetting.lock.find(::FlightDetailSetting.current.id)
            record.update!(update_params.merge(updated_by: current_user))
            record_audit!(record)
            record
          end
        end

        def update_params
          params.expect(flight_detail_setting: AUDITED_ATTRIBUTES.map(&:to_sym))
        end

        def record_audit!(record)
          changes = record.saved_changes.slice(*AUDITED_ATTRIBUTES)
          return if changes.empty?

          ::AuditEvent.create!(
            actor: current_user, entity_type: 'FlightDetailSetting', entity_id: record.id,
            action_code: 'flight_detail_setting_updated', request_id: request.request_id,
            occurred_at: Time.current, metadata: { changes: changes }
          )
        end

        def serialized(record)
          ::Admin::FlightDetailSettings::FlightDetailSettingSerializer.new(record).as_json
        end
      end
    end
  end
end
