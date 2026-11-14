# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets a developer see and correct a candidate's recorded medical
      # appointment, QVC appointment and flight details from the Overview tab,
      # without moving the candidate. Each change needs a reason, is audited,
      # and texts the candidate unless `notify_candidate` is false.
      class CandidateWorkflowCorrectionsController < ProtectedStaffController
        COMMON_PARAMS = %i[reason notify_candidate].freeze
        SERVICES = {
          medical_appointment: ::CandidateWorkflows::Corrections::MedicalAppointmentService,
          qvc_appointment: ::CandidateWorkflows::Corrections::QvcAppointmentService,
          flight_detail: ::CandidateWorkflows::Corrections::FlightDetailService
        }.freeze
        VALUE_PARAMS = {
          medical_appointment: %i[center_name center_address appointment_date appointment_time],
          qvc_appointment: %i[center_name center_address appointment_date appointment_time],
          flight_detail: %i[airline flight_number sector flight_date ticket]
        }.freeze

        def show
          authorize candidate, :show?, policy_class: ::Admin::WorkflowCorrectionPolicy

          render_success(data: serialized)
        end

        def medical_appointment = correct(:medical_appointment)
        def qvc_appointment = correct(:qvc_appointment)
        def flight_detail = correct(:flight_detail)

        private

        def correct(kind)
          authorize candidate, :update?, policy_class: ::Admin::WorkflowCorrectionPolicy

          SERVICES.fetch(kind).call(actor: current_user, candidate:, request_id: request.request_id,
                                    values: correction_params(kind))
          render_success(data: serialized)
        end

        def correction_params(kind)
          params.expect(workflow_correction: COMMON_PARAMS + VALUE_PARAMS.fetch(kind)).to_h
        end

        def candidate
          @candidate ||= policy_scope(::Candidate, policy_scope_class: ::Admin::CandidateWorkflowPolicy::Scope)
                         .find_by!(public_id: params.expect(:candidate_id))
        end

        def serialized
          ::Admin::WorkflowCorrections::WorkflowCorrectionSerializer.new(
            candidate:, assignment: candidate.current_assignment&.reload
          ).as_json
        end
      end
    end
  end
end
