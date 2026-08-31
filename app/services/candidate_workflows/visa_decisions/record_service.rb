# frozen_string_literal: true

module CandidateWorkflows
  module VisaDecisions
    # rubocop:disable Metrics/ClassLength
    class RecordService < ApplicationService
      Params = Struct.new(
        :actor,
        :candidate,
        :outcome_code,
        :decision_date,
        :rejection_reason_code,
        :visa_copy,
        :expected_current_stage_code,
        :request_id,
        :note,
        keyword_init: true
      )

      def initialize(**params)
        @params = Params.new(
          **params,
          outcome_code: normalized_code(params[:outcome_code]),
          decision_date: params[:decision_date].to_s,
          rejection_reason_code: normalized_code(params[:rejection_reason_code]),
          note: params[:note].to_s.strip.presence
        )
      end

      def call
        validate_actor!
        validate_payload!

        CandidateAssignment.transaction do
          record_decision!
        end
      end

      private

      def validate_actor!
        raise InactiveAccountError unless @params.actor&.active_staff_account?
        raise ForbiddenError unless @params.actor.permission?('manage_workflow')
      end

      def validate_payload!
        validate_expected_current_stage_code!
        validate_outcome_code!
        validate_decision_date!
        validate_rejection_reason! if rejected?
        raise DocumentAttachmentMissingError if issued? && @params.visa_copy.blank?
      end

      def validate_expected_current_stage_code!
        return if @params.expected_current_stage_code.present?

        raise_validation_error(
          'candidate_visa_decision.expected_current_stage_code',
          'api.errors.expected_current_stage_code_required'
        )
      end

      def validate_outcome_code!
        return if CandidateVisaDecision::OUTCOME_CODES.include?(@params.outcome_code)

        raise_validation_error(
          'candidate_visa_decision.outcome_code',
          'api.errors.workflow_transition_evidence_enum_invalid'
        )
      end

      def validate_decision_date!
        Date.iso8601(@params.decision_date)
      rescue ArgumentError
        raise_validation_error(
          'candidate_visa_decision.decision_date',
          'api.errors.workflow_transition_evidence_date_invalid'
        )
      end

      def validate_rejection_reason!
        if @params.rejection_reason_code.blank?
          raise_validation_error('candidate_visa_decision.rejection_reason_code',
                                 'api.errors.visa_rejection_reason_required')
        end
        return if CandidateVisaDecision::REJECTION_REASON_CODES.include?(@params.rejection_reason_code)

        raise_validation_error(
          'candidate_visa_decision.rejection_reason_code',
          'api.errors.workflow_transition_evidence_enum_invalid'
        )
      end

      def raise_validation_error(field, translation_key)
        raise ValidationError.new(field:, message: I18n.t(translation_key))
      end

      def issued? = @params.outcome_code == 'issued'

      def rejected? = @params.outcome_code == 'rejected'

      def record_decision!
        result = transition_to_visa_issued_or_rejected
        decision = locate_decision(result.fetch(:history_entry))
        attach_visa_copy!(decision)
        decision_result(decision, result.fetch(:snapshot))
      end

      def transition_to_visa_issued_or_rejected
        TransitionService.call(
          actor: @params.actor,
          candidate: @params.candidate,
          to_stage_code: 'visa_issued_or_rejected',
          expected_current_stage_code: @params.expected_current_stage_code,
          request_id: @params.request_id,
          note: @params.note,
          evidence: evidence_hash
        )
      end

      def evidence_hash
        {
          visa_outcome_code: @params.outcome_code,
          visa_outcome_date: @params.decision_date,
          rejection_reason_code: @params.rejection_reason_code
        }.compact
      end

      def locate_decision(history_entry)
        CandidateVisaDecision.find_by!(candidate_stage_history_id: history_entry.id)
      end

      def attach_visa_copy!(decision)
        return if @params.visa_copy.blank?

        decision.visa_copy.attach(@params.visa_copy)
      end

      def normalized_code(value) = value.to_s.strip.downcase.presence

      def decision_result(decision, snapshot)
        { visa_decision: decision.reload, snapshot: snapshot }
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
