# frozen_string_literal: true

module CandidateWorkflows
  module StageRequirements
    EVIDENCE_REQUIREMENTS = {
      'qvc_appointment_booked' => %w[appointment_date],
      'qvc_completed_outcome_received' => %w[qvc_outcome_code qvc_outcome_date],
      'visa_issued_or_rejected' => %w[visa_outcome_code visa_outcome_date],
      'appeared_for_protection' => %w[appeared_for_protection_on],
      'protected_ready_to_fly' => %w[protected_on],
      'flight_details_uploaded' => %w[flight_reference flight_date],
      'mobilized' => %w[mobilized_on]
    }.freeze

    module_function

    def required_fields_for(stage_code) = EVIDENCE_REQUIREMENTS.fetch(stage_code.to_s, [])
  end
end
