# frozen_string_literal: true

module CandidateWorkflows
  module FlightDetails
    class RecordService < ApplicationService
      Params = Struct.new(
        :actor,
        :candidate,
        :airline,
        :flight_number,
        :sector,
        :flight_date,
        :ticket,
        :expected_current_stage_code,
        :request_id,
        :note,
        keyword_init: true
      )

      def initialize(**params)
        @params = Params.new(
          **params,
          airline: normalized_string(params[:airline]),
          flight_number: normalized_string(params[:flight_number]),
          sector: normalized_string(params[:sector]),
          flight_date: params[:flight_date].to_s,
          note: params[:note].to_s.strip.presence
        )
      end

      def call
        validate_actor!
        validate_payload!

        CandidateAssignment.transaction do
          record_flight_detail!
        end
      end

      private

      def validate_actor!
        raise InactiveAccountError unless @params.actor&.active_staff_account?
        raise ForbiddenError unless @params.actor.permission?('manage_workflow')
      end

      def validate_payload!
        validate_expected_current_stage_code!
        validate_presence!('airline', @params.airline)
        validate_presence!('flight_number', @params.flight_number)
        validate_presence!('sector', @params.sector)
        validate_flight_date!
        raise DocumentAttachmentMissingError if @params.ticket.blank?
      end

      def validate_expected_current_stage_code!
        return if @params.expected_current_stage_code.present?

        raise_validation_error(
          'candidate_flight_detail.expected_current_stage_code',
          'api.errors.expected_current_stage_code_required'
        )
      end

      def validate_presence!(field_name, value)
        return if value.present?

        raise_validation_error(
          "candidate_flight_detail.#{field_name}",
          'api.errors.workflow_transition_evidence_value_invalid'
        )
      end

      def validate_flight_date!
        DateTime.iso8601(@params.flight_date)
      rescue ArgumentError, TypeError
        raise_validation_error(
          'candidate_flight_detail.flight_date',
          'api.errors.workflow_transition_evidence_date_invalid'
        )
      end

      def raise_validation_error(field, translation_key)
        raise ValidationError.new(field:, message: I18n.t(translation_key))
      end

      def record_flight_detail!
        result = transition_to_flight_details_uploaded
        detail = locate_detail(result.fetch(:history_entry))
        detail.ticket.attach(@params.ticket)
        flight_detail_result(detail, result.fetch(:snapshot))
      end

      def transition_to_flight_details_uploaded
        TransitionService.call(
          actor: @params.actor,
          candidate: @params.candidate,
          to_stage_code: 'flight_details_uploaded',
          expected_current_stage_code: @params.expected_current_stage_code,
          request_id: @params.request_id,
          note: @params.note,
          evidence: evidence_hash
        )
      end

      def evidence_hash
        {
          airline: @params.airline,
          flight_reference: @params.flight_number,
          sector: @params.sector,
          flight_date: @params.flight_date
        }
      end

      def locate_detail(history_entry)
        CandidateFlightDetail.find_by!(candidate_stage_history_id: history_entry.id)
      end

      def normalized_string(value) = value.to_s.strip.presence

      def flight_detail_result(detail, snapshot)
        { flight_detail: detail.reload, snapshot: snapshot }
      end
    end
  end
end
