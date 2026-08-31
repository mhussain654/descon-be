# frozen_string_literal: true

module Api
  module V1
    module Admin
      # rubocop:disable Metrics/ClassLength
      class CandidateFlightDetailsController < ProtectedStaffController
        include IdempotentRequestHandling

        FLIGHT_DETAIL_PARAMS = %i[
          airline
          flight_number
          sector
          flight_date
          ticket
          expected_current_stage_code
          note
        ].freeze

        MOBILIZATION_PARAMS = %i[mobilized_on expected_current_stage_code note].freeze

        def show
          authorize candidate, :history?, policy_class: ::Admin::CandidateWorkflowPolicy
          set_state_headers
          render_success(data: flight_detail_payload)
        end

        def create
          authorize candidate, :create_transition?, policy_class: ::Admin::CandidateWorkflowPolicy

          render_idempotent_response(
            scope: 'admin.candidate_flight_details.create',
            subject: current_user,
            fingerprint: create_fingerprint,
            required: true
          ) do
            result = ::CandidateWorkflows::FlightDetails::RecordService.call(**record_payload)
            success_response(result:, status: :created)
          end
        end

        def update
          authorize candidate, :create_transition?, policy_class: ::Admin::CandidateWorkflowPolicy

          render_idempotent_response(
            scope: 'admin.candidate_flight_details.update',
            subject: current_user,
            fingerprint: update_fingerprint,
            required: true
          ) do
            result = ::CandidateWorkflows::FlightDetails::MobilizeService.call(**mobilize_payload)
            success_response(result:, status: :ok)
          end
        end

        private

        def success_response(result:, status:)
          set_state_headers
          success_payload(data: ::CandidateWorkflows::AdminFlightDetailResultSerializer.new(result).as_json, status:)
        end

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def flight_detail_params
          params.expect(candidate_flight_detail: FLIGHT_DETAIL_PARAMS)
        end

        def mobilization_params
          params.expect(candidate_flight_detail: MOBILIZATION_PARAMS)
        end

        def create_fingerprint
          ::CandidateWorkflows::FlightDetails::UploadFingerprint.call(
            request:,
            candidate_public_id: candidate.public_id,
            payload: flight_detail_params.except(:ticket).to_h.deep_symbolize_keys,
            uploaded_file: flight_detail_params[:ticket]
          )
        end

        def update_fingerprint
          {
            candidate_public_id: candidate.public_id,
            action: action_name,
            payload: mobilization_params.to_h.deep_symbolize_keys
          }.to_json
        end

        def record_payload
          {
            actor: current_user,
            candidate: candidate,
            request_id: request.request_id
          }.merge(flight_detail_fields)
        end

        def flight_detail_fields
          {
            airline: flight_detail_params[:airline],
            flight_number: flight_detail_params[:flight_number],
            sector: flight_detail_params[:sector],
            flight_date: flight_detail_params[:flight_date],
            ticket: flight_detail_params[:ticket],
            expected_current_stage_code: flight_detail_params[:expected_current_stage_code],
            note: flight_detail_params[:note]
          }
        end

        def mobilize_payload
          {
            actor: current_user,
            candidate: candidate,
            mobilized_on: mobilization_params[:mobilized_on],
            expected_current_stage_code: mobilization_params[:expected_current_stage_code],
            request_id: request.request_id,
            note: mobilization_params[:note]
          }
        end

        def flight_detail_payload
          assignment = candidate.current_assignment
          {
            candidate_id: candidate.public_id,
            assignment_id: assignment&.public_id,
            flight_detail: serialized_flight_detail(assignment),
            updated_at: serialized_updated_at(assignment)
          }
        end

        def serialized_flight_detail(assignment)
          return if assignment.blank?

          ::CandidateWorkflows::AdminFlightDetailSerializer.new(assignment.candidate_flight_detail).as_json
        end

        def serialized_updated_at(assignment)
          updated_at = assignment&.updated_at
          updated_at&.utc&.iso8601
        end

        def set_state_headers
          set_private_state_headers(
            updated_at: candidate.current_assignment&.reload&.updated_at,
            etag_key: "#{candidate.public_id}:flight_detail"
          )
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
