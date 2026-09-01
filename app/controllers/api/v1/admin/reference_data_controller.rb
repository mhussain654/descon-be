# frozen_string_literal: true

module Api
  module V1
    module Admin
      class ReferenceDataController < ProtectedStaffController
        CREATE_PARAMS = %i[code name_en name_ur].freeze
        UPDATE_PARAMS = %i[name_en name_ur expected_updated_at].freeze

        def index
          authorize :reference_data, :index?, policy_class: ::Admin::ReferenceDataPolicy

          render_success(data: records.order(:code).map { |record| lookup_serialized(record) })
        end

        def create
          authorize :reference_data, :create?, policy_class: ::Admin::ReferenceDataPolicy

          render_idempotent_response(
            scope: "admin.reference_data.#{record_class.name.underscore}.create",
            subject: current_user,
            fingerprint: create_params.to_h.to_json,
            required: true
          ) { success_payload(data: serialized(mutate(:create, create_params)), status: :created) }
        end

        def update
          authorize :reference_data, :update?, policy_class: ::Admin::ReferenceDataPolicy

          updated = mutate(:update, update_params.except(:expected_updated_at))
          apply_reference_data_state_headers(updated)
          render_success(data: serialized(updated))
        end

        def retirement
          authorize :reference_data, :retire?, policy_class: ::Admin::ReferenceDataPolicy

          retired = mutate(:retire, {})
          apply_reference_data_state_headers(retired)
          render_success(data: serialized(retired))
        end

        private

        def records
          policy_scope(record_class, policy_scope_class: ::Admin::ReferenceDataPolicy::Scope)
        end

        def record
          @record ||= record_class.find_by!(code: params.expect(:code))
        end

        def mutate(action, attributes)
          ::Admin::ReferenceData::MutationService.call(
            actor: current_user,
            record: action == :create ? nil : record,
            record_class:,
            action:,
            attributes: attributes.to_h,
            expected_updated_at: update_params[:expected_updated_at],
            request_id: request.request_id
          )
        end

        def create_params
          params.expect(reference_data: CREATE_PARAMS)
        end

        def update_params
          params.fetch(:reference_data, {}).permit(*UPDATE_PARAMS)
        end

        def serialized(record)
          {
            code: record.code,
            name: record.name_for,
            active: record.active,
            updated_at: record.updated_at.utc.iso8601
          }
        end

        def lookup_serialized(record)
          { code: record.code, name: record.name_for }
        end

        def apply_reference_data_state_headers(record)
          set_private_state_headers(updated_at: record.updated_at, etag_key: "#{record_class.name}:#{record.code}")
        end
      end
    end
  end
end
