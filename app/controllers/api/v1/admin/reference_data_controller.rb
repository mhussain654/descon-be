# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Shared base for simple lookup/reference-data resources (e.g.
      # projects, crafts, countries): list, create, update and retire a
      # coded lookup record. Subclasses only override `record_class`.
      class ReferenceDataController < ProtectedStaffController
        CREATE_PARAMS = %i[code name_en name_ur].freeze
        UPDATE_PARAMS = %i[name_en name_ur expected_updated_at].freeze

        # Lists all reference-data records of this type, ordered by code.
        def index
          authorize :reference_data, :index?, policy_class: ::Admin::ReferenceDataPolicy

          render_success(data: records.order(:code).map { |record| lookup_serialized(record) })
        end

        # Creates a new reference-data record; deduplicated via the
        # idempotency fingerprint of the submitted attributes.
        def create
          authorize :reference_data, :create?, policy_class: ::Admin::ReferenceDataPolicy

          render_idempotent_response(
            scope: "admin.reference_data.#{record_class.name.underscore}.create",
            subject: current_user,
            fingerprint: create_params.to_h.to_json,
            required: true
          ) { success_payload(data: serialized(mutate(:create, create_params)), status: :created) }
        end

        # Updates an existing reference-data record's names, guarded by an
        # optimistic-concurrency check on `expected_updated_at`.
        def update
          authorize :reference_data, :update?, policy_class: ::Admin::ReferenceDataPolicy

          updated = mutate(:update, update_params.except(:expected_updated_at))
          apply_reference_data_state_headers(updated)
          render_success(data: serialized(updated))
        end

        # Retires (soft-deactivates) an existing reference-data record.
        def retirement
          authorize :reference_data, :retire?, policy_class: ::Admin::ReferenceDataPolicy

          retired = mutate(:retire, {})
          apply_reference_data_state_headers(retired)
          render_success(data: serialized(retired))
        end

        private

        # Scopes the reference-data table to what the current staff member
        # is authorized to view.
        def records
          policy_scope(record_class, policy_scope_class: ::Admin::ReferenceDataPolicy::Scope)
        end

        # Loads the record named by the route's `code` param, raising if no
        # match exists.
        def record
          @record ||= record_class.find_by!(code: params.expect(:code))
        end

        # Delegates the create/update/retire mutation to the shared
        # reference-data mutation service.
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

        # Permits the params accepted when creating a record.
        def create_params
          params.expect(reference_data: CREATE_PARAMS)
        end

        # Permits the params accepted when updating a record.
        def update_params
          params.fetch(:reference_data, {}).permit(*UPDATE_PARAMS)
        end

        # Serializes a reference-data record for the API response.
        def serialized(record)
          {
            code: record.code,
            name: record.name_for,
            active: record.active,
            updated_at: record.updated_at.utc.iso8601
          }
        end

        # Serializes a reference-data record for the lightweight index/
        # lookup list (code and name only).
        def lookup_serialized(record)
          { code: record.code, name: record.name_for }
        end

        # Sets the private cache/ETag headers for a mutated reference-data
        # record.
        def apply_reference_data_state_headers(record)
          set_private_state_headers(updated_at: record.updated_at, etag_key: "#{record_class.name}:#{record.code}")
        end
      end
    end
  end
end
