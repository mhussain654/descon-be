# frozen_string_literal: true

module CandidateWorkflows
  # rubocop:disable Metrics/ClassLength
  class TransitionSideEffectRecorder < ApplicationService
    def initialize(history_entry:, context:, transition:)
      @history_entry = history_entry
      @context = context
      @transition = transition
    end

    def call
      record_qvc_attempt!
      record_protection_record!
      record_visa_decision!
      record_flight_detail!
      PostTransitionEventRecorder.call(
        history_entry: @history_entry,
        context: @context,
        transition: @transition
      )
    end

    private

    def record_qvc_attempt!
      create_qvc_attempt! if destination_stage_code == 'qvc_appointment_booked'
      complete_qvc_attempt! if destination_stage_code == 'qvc_completed_outcome_received'
    end

    def create_qvc_attempt!
      attempt = assignment.candidate_qvc_attempts.create!(qvc_attempt_attributes)
      record_qvc_attempt_audit!(event: :scheduled, attempt:)
    end

    def complete_qvc_attempt!
      attempt = assignment.candidate_qvc_attempts.open_attempts.latest_first.first
      raise InvalidWorkflowTransitionError.new(field: 'candidate_workflow_transition.to_stage_code') if attempt.blank?

      update_qvc_attempt!(attempt)
      update_assignment_qvc_summary!

      record_qvc_attempt_audit!(event: :completed, attempt:)
    end

    def record_protection_record!
      record_protection_appearance! if destination_stage_code == 'appeared_for_protection'
      record_ready_to_fly! if destination_stage_code == 'protected_ready_to_fly'
    end

    def record_protection_appearance!
      protection_record.update!(
        appeared_on: Date.iso8601(evidence.fetch('appeared_for_protection_on')),
        appeared_recorded_at: @transition.fetch(:transitioned_at),
        appeared_recorded_by: @history_entry.actor || assignment.created_by
      )
    end

    def record_ready_to_fly!
      protection_record.update!(
        protected_on: Date.iso8601(evidence.fetch('protected_on')),
        ready_to_fly_at: @transition.fetch(:transitioned_at),
        ready_recorded_by: @history_entry.actor || assignment.created_by
      )
    end

    def protection_record
      @protection_record ||= assignment.candidate_protection_record || assignment.build_candidate_protection_record
    end

    def record_visa_decision!
      return unless destination_stage_code == 'visa_issued_or_rejected'

      decision = assignment.candidate_visa_decisions.create!(visa_decision_attributes)
      VisaDecisionAuditRecorder.call(
        actor:,
        request_id: @transition.fetch(:request_id),
        context: { candidate:, assignment:, decision: }
      )
    end

    def visa_decision_attributes
      {
        candidate_stage_history: @history_entry,
        recorded_by: actor,
        outcome_code: evidence.fetch('visa_outcome_code'),
        decision_date: Date.iso8601(evidence.fetch('visa_outcome_date')),
        rejection_reason_code: evidence['rejection_reason_code']
      }
    end

    def record_flight_detail!
      create_flight_detail! if destination_stage_code == 'flight_details_uploaded'
      mobilize_flight_detail! if destination_stage_code == 'mobilized'
    end

    def create_flight_detail!
      detail = assignment.create_candidate_flight_detail!(flight_detail_attributes)
      record_flight_detail_audit!(event: :recorded, detail:)
    end

    def flight_detail_attributes
      {
        candidate_stage_history: @history_entry,
        recorded_by: actor,
        airline: evidence.fetch('airline'),
        flight_number: evidence.fetch('flight_reference'),
        sector: evidence.fetch('sector'),
        flight_departure_at: DateTime.iso8601(evidence.fetch('flight_date'))
      }
    end

    def mobilize_flight_detail!
      detail = assignment.candidate_flight_detail
      raise InvalidWorkflowTransitionError.new(field: 'candidate_workflow_transition.to_stage_code') if detail.blank?

      detail.update!(
        mobilized_on: Date.iso8601(evidence.fetch('mobilized_on')),
        mobilized_stage_history: @history_entry,
        mobilized_recorded_by: actor
      )
      record_flight_detail_audit!(event: :mobilized, detail:)
    end

    def record_flight_detail_audit!(event:, detail:)
      FlightDetailAuditRecorder.call(
        event:,
        actor:,
        request_id: @transition.fetch(:request_id),
        context: { candidate:, assignment:, detail: }
      )
    end

    def next_attempt_number
      assignment.candidate_qvc_attempts.maximum(:attempt_number).to_i + 1
    end

    def qvc_attempt_attributes
      {
        scheduled_by: actor,
        attempt_number: next_attempt_number,
        appointment_date: Date.iso8601(evidence.fetch('appointment_date')),
        internal_note: @history_entry.note
      }
    end

    def record_qvc_attempt_audit!(event:, attempt:)
      QvcAttemptAuditRecorder.call(
        event:,
        actor: @history_entry.actor,
        request_id: @transition.fetch(:request_id),
        context: { candidate:, assignment:, attempt: }
      )
    end

    def actor
      @history_entry.actor || assignment.created_by
    end

    def update_qvc_attempt!(attempt)
      attempt.update!(
        outcome_code: normalized_qvc_outcome_code(evidence.fetch('qvc_outcome_code')),
        outcome_recorded_at: transitioned_at,
        outcome_recorded_by: actor,
        internal_note: @history_entry.note
      )
    end

    def update_assignment_qvc_summary!
      assignment.update!(
        qvc_outcome_code: normalized_qvc_outcome_code(evidence.fetch('qvc_outcome_code')),
        qvc_outcome_date: transitioned_at.to_date,
        updated_at: transitioned_at
      )
    end

    def transitioned_at
      @transition.fetch(:transitioned_at)
    end

    def normalized_qvc_outcome_code(value)
      normalized = value.to_s.strip.downcase
      return 're_medical' if normalized == 're_medical_required'

      normalized
    end

    def destination_stage_code
      @context.fetch(:destination_stage).code
    end

    def assignment
      @context.fetch(:assignment)
    end

    def candidate
      @context.fetch(:candidate)
    end

    def evidence
      @transition.fetch(:evidence)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
