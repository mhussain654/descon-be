# frozen_string_literal: true

module Api
  module V1
    module Admin
      class CandidatesController < ProtectedStaffController
        include IdempotentRequestHandling

        CREATE_PARAMS = %i[
          full_name cnic mobile_number passport_number preferred_locale
          country_code project_code craft_code reference_number
        ].freeze

        UPDATE_PARAMS = %i[
          full_name mobile_number passport_number preferred_locale
          country_code project_code craft_code expected_updated_at
        ].freeze

        def show
          authorize candidate, :show?, policy_class: ::Admin::CandidatePolicy

          set_state_headers
          render_success(data: serialized_candidate(candidate))
        end

        def create
          authorize ::Candidate, :create?, policy_class: ::Admin::CandidatePolicy

          render_idempotent_response(
            scope: 'admin.candidates.create',
            subject: current_user,
            fingerprint: create_params.to_h.deep_symbolize_keys.to_json,
            required: true
          ) { create_payload }
        end

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

        def create_payload
          candidate = ::Admin::Candidates::CreateService.call(
            actor: current_user,
            request_id: request.request_id,
            **create_params.to_h.symbolize_keys
          )
          set_state_headers(candidate:)
          success_payload(data: serialized_candidate(candidate), status: :created)
        end

        def serialized_candidate(candidate)
          ::Admin::CandidateSerializer.new(candidate).as_json
        end

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidatePolicy::Scope)
                         .find_by!(public_id: params.expect(:id))
        end

        def create_params
          params.expect(candidate: CREATE_PARAMS)
        end

        def update_params
          params.expect(candidate: UPDATE_PARAMS)
        end

        def set_state_headers(candidate: self.candidate)
          assignment = candidate.current_assignment
          updated_at = [candidate.updated_at, assignment&.updated_at].compact.max
          set_private_state_headers(updated_at:, etag_key: candidate.public_id)
        end
      end
    end
  end
end
