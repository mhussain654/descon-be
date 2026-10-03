# frozen_string_literal: true

module CandidateWorkflows
  class StateSerializer
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def as_json(*) = base_attributes.merge(updated_at: @snapshot.updated_at)

    private

    def base_attributes = workflow_attributes.merge(outcomes: serialized_outcomes).merge(progress_attributes)

    def workflow_attributes
      {
        candidate_id: @snapshot.candidate.public_id,
        assignment_id: @snapshot.assignment&.public_id,
        candidate_status: @snapshot.candidate_status,
        mobilization_process: MobilizationProcessSerializer.new(@snapshot.mobilization_process).as_json,
        current_stage: @snapshot.current_stage,
        timeline: @snapshot.timeline,
        qvc_attempts: serialized_qvc_attempts,
        protection: serialized_protection
      }
    end

    def progress_attributes
      {
        completed_count: @snapshot.completed_count,
        total_count: @snapshot.total_count,
        progress_percentage: @snapshot.progress_percentage
      }
    end

    def serialized_qvc_attempts
      @snapshot.qvc_attempts.map { |attempt| QvcAttemptSerializer.new(attempt).as_json }
    end

    # The latest medical and visa decisions: a negative one means the candidate
    # is held at that outcome stage until staff record a new decision.
    def serialized_outcomes
      {
        medical: @snapshot.medical_result && MedicalResultSerializer.new(@snapshot.medical_result).as_json,
        visa: @snapshot.visa_decision && VisaDecisionSerializer.new(@snapshot.visa_decision).as_json
      }
    end

    def serialized_protection
      ProtectionSerializer.new(@snapshot.protection_record).as_json
    end
  end
end
