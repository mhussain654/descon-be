# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets staff list, view, register and update candidates in the recruitment pipeline.
      class CandidatesController < ProtectedStaffController
        include IdempotentRequestHandling

        CREATE_PARAMS = %i[
          full_name cnic mobile_number passport_number preferred_locale
          next_of_kin_name next_of_kin_relationship next_of_kin_mobile_number next_of_kin_cnic
          country_code project_code craft_code reference_number
        ].freeze

        UPDATE_PARAMS = %i[
          full_name mobile_number passport_number preferred_locale
          next_of_kin_name next_of_kin_relationship next_of_kin_mobile_number next_of_kin_cnic
          country_code project_code craft_code expected_updated_at
        ].freeze

        # Returns a paginated, filtered list of candidates within the staff member's authorized scope.
        def index
          authorize ::Candidate, :index?, policy_class: ::Admin::CandidatePolicy

          query = ::Admin::Candidates::IndexQuery.new(
            scope: policy_scope(::Candidate, policy_scope_class: ::Admin::CandidatePolicy::Scope), params:
          )
          candidates = query.call
          data = candidates.map { |candidate| serialized_candidate(candidate) }
          render_collection(data:, pagination: query.pagination, meta: { applied_filters: query.applied_filters })
        end

        # Returns the details of a single candidate identified by public id.
        def show
          authorize candidate, :show?, policy_class: ::Admin::CandidatePolicy

          set_state_headers
          render_success(data: serialized_candidate(candidate))
        end

        # Registers a new candidate, idempotently, based on the submitted identity and assignment fields.
        def create
          authorize ::Candidate, :create?, policy_class: ::Admin::CandidatePolicy

          render_idempotent_response(
            scope: 'admin.candidates.create',
            subject: current_user,
            fingerprint: create_params.to_h.deep_symbolize_keys.to_json,
            required: true
          ) { create_payload }
        end

        # Updates an existing candidate's profile/assignment fields and returns the updated record.
        def update
          authorize candidate, :update?, policy_class: ::Admin::CandidatePolicy

          updated = ::Admin::Candidates::UpdateService.call(
            actor: current_user,
            candidate:,
            **update_params.to_h.symbolize_keys
          )
          set_state_headers(candidate: updated)
          render_success(data: serialized_candidate(updated))
        end

        private

        # Creates the candidate via the create service and builds the 201 response body.
        def create_payload
          candidate = ::Admin::Candidates::CreateService.call(
            actor: current_user,
            request_id: request.request_id,
            **create_params.to_h.symbolize_keys
          )
          set_state_headers(candidate:)
          success_payload(data: serialized_candidate(candidate), status: :created)
        end

        # Serializes a candidate record for the admin API response shape.
        def serialized_candidate(candidate)
          ::Admin::CandidateSerializer.new(candidate).as_json
        end

        # Loads the candidate for the current action within the staff member's authorized scope,
        # raising if not found.
        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidatePolicy::Scope)
                         .find_by!(public_id: params.expect(:id))
        end

        # Allowlists the fields accepted when registering a new candidate.
        def create_params
          params.expect(candidate: CREATE_PARAMS)
        end

        # Allowlists the fields accepted when updating an existing candidate.
        def update_params
          params.expect(candidate: UPDATE_PARAMS)
        end

        # Sets caching/concurrency headers (Last-Modified/ETag) from the candidate's and its
        # current assignment's most recent update time.
        def set_state_headers(candidate: self.candidate)
          assignment = candidate.current_assignment
          updated_at = [candidate.updated_at, assignment&.updated_at].compact.max
          set_private_state_headers(updated_at:, etag_key: candidate.public_id)
        end
      end
    end
  end
end
