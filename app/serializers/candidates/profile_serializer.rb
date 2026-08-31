# frozen_string_literal: true

module Candidates
  class ProfileSerializer
    def initialize(candidate)
      @candidate = candidate
    end

    def as_json(*)
      profile_attributes.merge(
        current_workflow_stage: serialized_workflow_stage,
        payment: serialized_payment
      )
    end

    private

    def profile_attributes
      {
        id: @candidate.public_id,
        full_name: @candidate.full_name,
        masked_cnic: Candidates::CnicMasker.call(@candidate.cnic),
        reference_number: current_assignment&.reference_number,
        preferred_locale: @candidate.preferred_locale,
        candidate_status: @candidate.status_code,
        active: @candidate.active
      }
    end

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

    def serialized_payment
      Payments::EligibilitySerializer.new(Payments::EligibilityService.call(candidate: @candidate)).as_json
    end
  end
end
