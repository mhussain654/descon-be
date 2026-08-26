# frozen_string_literal: true

module Candidates
  class ProfileSerializer
    def initialize(candidate)
      @candidate = candidate
    end

    def as_json(*)
      {
        id: @candidate.public_id,
        full_name: @candidate.full_name,
        masked_cnic: Candidates::CnicMasker.call(@candidate.cnic),
        reference_number: current_assignment&.reference_number,
        preferred_locale: @candidate.preferred_locale,
        candidate_status: @candidate.status_code,
        current_workflow_stage: serialized_workflow_stage,
        active: @candidate.active
      }
    end

    private

    def current_assignment
      @current_assignment ||= @candidate.current_assignment
    end

    def serialized_workflow_stage
      stage = current_assignment&.current_workflow_stage
      return if stage.blank?

      {
        code: stage.code,
        name: stage.name_for
      }
    end
  end
end
