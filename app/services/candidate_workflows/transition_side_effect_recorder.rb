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
      PostTransitionEventRecorder.call(
        history_entry: @history_entry,
        context: @context,
        transition: @transition
      )
    end

    private

    def record_qvc_attempt!
      return create_qvc_attempt! if destination_stage_code == 'qvc_appointment_booked'
      return complete_qvc_attempt! if destination_stage_code == 'qvc_completed_outcome_received'
    end

    def create_qvc_attempt!
      attempt = assignment.candidate_qvc_attempts.create!(
        scheduled_by: @history_entry.actor || assignment.created_by,
        attempt_number: next_attempt_number,
        appointment_date: Date.iso8601(evidence.fetch('appointment_date')),
        internal_note: @history_entry.note
      )

      QvcAttemptAuditRecorder.call(
        event: :scheduled,
        candidate: candidate,
        assignment:,
        attempt:,
        actor: @history_entry.actor,
        request_id: @transition.fetch(:request_id)
      )
    end

    def complete_qvc_attempt!
      attempt = assignment.candidate_qvc_attempts.open_attempts.latest_first.first
      raise InvalidWorkflowTransitionError.new(field: 'candidate_workflow_transition.to_stage_code') if attempt.blank?

      recorded_at = @transition.fetch(:transitioned_at)
      outcome_code = normalized_qvc_outcome_code(evidence.fetch('qvc_outcome_code'))
      attempt.update!(
        outcome_code:,
        outcome_recorded_at: recorded_at,
        outcome_recorded_by: @history_entry.actor || assignment.created_by,
        internal_note: @history_entry.note
      )
      assignment.update!(
        qvc_outcome_code: outcome_code,
        qvc_outcome_date: recorded_at.to_date,
        updated_at: recorded_at
      )

      QvcAttemptAuditRecorder.call(
        event: :completed,
        candidate: candidate,
        assignment:,
        attempt:,
        actor: @history_entry.actor,
        request_id: @transition.fetch(:request_id)
      )
    end

    def record_protection_record!
      return record_protection_appearance! if destination_stage_code == 'appeared_for_protection'
      return record_ready_to_fly! if destination_stage_code == 'protected_ready_to_fly'
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

    def next_attempt_number
      assignment.candidate_qvc_attempts.maximum(:attempt_number).to_i + 1
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
