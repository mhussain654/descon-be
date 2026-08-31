# frozen_string_literal: true

module CandidateWorkflows
  module FlightDetails
    class MobilizeService < ApplicationService
      Params = Struct.new(
        :actor,
        :candidate,
        :mobilized_on,
        :expected_current_stage_code,
        :request_id,
        :note,
        keyword_init: true
      )

      def initialize(**params)
        @params = Params.new(
          **params,
          mobilized_on: params[:mobilized_on].to_s,
          note: params[:note].to_s.strip.presence
        )
      end

      def call
        validate_actor!
        validate_payload!

        CandidateAssignment.transaction do
          mobilize!
        end
      end

      private

      def validate_actor!
        raise InactiveAccountError unless @params.actor&.active_staff_account?
        raise ForbiddenError unless @params.actor.permission?('manage_workflow')
      end

      def validate_payload!
        validate_expected_current_stage_code!
        validate_mobilized_on!
      end

      def validate_expected_current_stage_code!
        return if @params.expected_current_stage_code.present?

        raise_validation_error(
          'candidate_flight_detail.expected_current_stage_code',
          'api.errors.expected_current_stage_code_required'
        )
      end

      def validate_mobilized_on!
        Date.iso8601(@params.mobilized_on)
      rescue ArgumentError
        raise_validation_error(
          'candidate_flight_detail.mobilized_on',
          'api.errors.workflow_transition_evidence_date_invalid'
        )
      end

      def raise_validation_error(field, translation_key)
        raise ValidationError.new(field:, message: I18n.t(translation_key))
      end

      def mobilize!
        detail = locked_flight_detail
        raise_already_mobilized! if detail.mobilized?
        validate_date_sequence!(detail)

        result = transition_to_mobilized
        { flight_detail: detail.reload, snapshot: result.fetch(:snapshot) }
      end

      def transition_to_mobilized
        TransitionService.call(
          actor: @params.actor,
          candidate: @params.candidate,
          to_stage_code: 'mobilized',
          expected_current_stage_code: @params.expected_current_stage_code,
          request_id: @params.request_id,
          note: @params.note,
          evidence: { mobilized_on: @params.mobilized_on }
        )
      end

      def locked_flight_detail
        candidate = Candidate.lock.find(@params.candidate.id)
        raise InactiveAccountError unless candidate.active?

        assignment_id = candidate.current_assignment&.id
        raise NoCurrentAssignmentError if assignment_id.blank?

        assignment = CandidateAssignment.lock.find(assignment_id)
        detail = assignment.candidate_flight_detail
        raise InvalidWorkflowTransitionError.new(field: 'candidate_flight_detail.id') if detail.blank?

        detail
      end

      def raise_already_mobilized!
        raise_validation_error('candidate_flight_detail.mobilized_on', 'api.errors.flight_detail_already_mobilized')
      end

      def validate_date_sequence!(detail)
        return if Date.iso8601(@params.mobilized_on) >= detail.flight_departure_at.to_date

        raise_validation_error('candidate_flight_detail.mobilized_on', 'api.errors.flight_mobilization_date_invalid')
      end
    end
  end
end
