# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Records and reports a candidate's flight/ticket details and final
      # mobilization date as they move through the deployment stages of
      # the recruitment workflow.
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

        # Returns the candidate's current flight detail (if any recorded)
        # along with the assignment it belongs to.
        def show
          authorize candidate, :history?, policy_class: ::Admin::CandidateWorkflowPolicy
          set_state_headers
          render_success(data: flight_detail_payload)
        end

        # Records the candidate's flight/ticket details (with the uploaded
        # ticket file); deduplicated via an upload fingerprint so a retried
        # request does not create a duplicate record.
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

        # Records the candidate's mobilization (deployment) date against
        # their existing flight detail; deduplicated via the idempotency
        # fingerprint.
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

        # Refreshes the state headers and serializes a create/update result
        # for the response.
        def success_response(result:, status:)
          set_state_headers
          success_payload(data: ::CandidateWorkflows::AdminFlightDetailResultSerializer.new(result).as_json, status:)
        end

        # Loads the candidate named in the route, scoped to what the current
        # staff member is authorized to view/manage.
        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        # Permits the flight/ticket params accepted on create.
        def flight_detail_params
          params.expect(candidate_flight_detail: FLIGHT_DETAIL_PARAMS)
        end

        # Permits the mobilization-date params accepted on update.
        def mobilization_params
          params.expect(candidate_flight_detail: MOBILIZATION_PARAMS)
        end

        # Builds the idempotency-key fingerprint for a flight-detail
        # create, including the uploaded ticket file so a re-upload with
        # different content is not treated as a duplicate.
        def create_fingerprint
          ::CandidateWorkflows::FlightDetails::UploadFingerprint.call(
            request:,
            candidate_public_id: candidate.public_id,
            payload: flight_detail_params.except(:ticket).to_h.deep_symbolize_keys,
            uploaded_file: flight_detail_params[:ticket]
          )
        end

        # Builds the idempotency-key fingerprint for a mobilization update.
        def update_fingerprint
          {
            candidate_public_id: candidate.public_id,
            action: action_name,
            payload: mobilization_params.to_h.deep_symbolize_keys
          }.to_json
        end

        # Assembles the arguments passed to the flight-detail record
        # service.
        def record_payload
          {
            actor: current_user,
            candidate: candidate,
            request_id: request.request_id
          }.merge(flight_detail_fields)
        end

        # Extracts the flight/ticket fields from the permitted params.
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

        # Assembles the arguments passed to the mobilization service.
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

        # Assembles the show-response body: candidate/assignment ids, the
        # serialized flight detail (if any), and its last-updated time.
        def flight_detail_payload
          assignment = candidate.current_assignment
          {
            candidate_id: candidate.public_id,
            assignment_id: assignment&.public_id,
            flight_detail: serialized_flight_detail(assignment),
            updated_at: serialized_updated_at(assignment)
          }
        end

        # Serializes the assignment's flight detail, or nil if the
        # candidate has no current assignment.
        def serialized_flight_detail(assignment)
          return if assignment.blank?

          ::CandidateWorkflows::AdminFlightDetailSerializer.new(assignment.candidate_flight_detail).as_json
        end

        # Formats the assignment's updated_at timestamp as UTC ISO8601, or
        # nil if there is no assignment.
        def serialized_updated_at(assignment)
          updated_at = assignment&.updated_at
          updated_at&.utc&.iso8601
        end

        # Sets the private cache/ETag headers for this candidate's flight
        # detail, keyed off the candidate's current assignment timestamp.
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
