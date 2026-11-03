# frozen_string_literal: true

module MobilizationProcesses
  # The approved, code-reviewed mobilization process versions (first release
  # seeds these instead of offering an admin workflow builder). A published
  # version is immutable: to change one, add a new definition with the next
  # `version` -- never edit a published entry in place (the Seeder refuses).
  #
  # The client's finalized flows (Nov 2026) give KSA, Qatar, UAE and Oman
  # each their own process. Every flow runs Enrolled -> Document Submission ->
  # Medical -> Mobilization Fee, then its own visa steps, then Protection ->
  # Pre Flight Brief -> Ready to Fly. UAE and Oman share the standard flow;
  # KSA adds Tasheer registration and Qatar adds the QVC steps. Countries the
  # client hasn't given a flow for (Kuwait, Azerbaijan, South Africa) resolve
  # to the provisional common process, which follows the standard flow.
  #
  # New versions only change which process a *new* assignment is attached
  # to; candidates already in a process stay on the version they started.
  module Definitions
    # What kind of action moves a candidate *into* each catalog stage, so
    # clients can pick the right form by `action_type`, never by country.
    ACTION_TYPES = {
      'registered' => 'none',
      'documents_pending' => 'document_submission',
      'documents_uploaded' => 'document_submission',
      'under_verification' => 'none',
      'verified' => 'none',
      'campaign_nomination' => 'nomination',
      'medical_pending' => 'medical_appointment',
      'medical_completed' => 'medical_outcome',
      'medical_appointment' => 'medical_appointment',
      'medical_fit' => 'medical_outcome',
      'gamca_medical_pending' => 'medical_appointment',
      'gamca_medical_completed' => 'medical_outcome',
      'e_number_processing' => 'e_number_processing',
      'e_number_requested' => 'e_number_request',
      'e_number_received' => 'e_number_received',
      'biometric_completed' => 'biometric_completion',
      'visa_stamping_case_prepared' => 'visa_case_preparation',
      'fee_pending' => 'payment',
      'fee_paid' => 'payment',
      'documents_shared_with_qatar_bu' => 'none',
      'qvc_appointment_booked' => 'qvc_appointment',
      'qvc_completed_outcome_received' => 'qvc_outcome',
      'visa_processing' => 'visa_processing',
      'visa_stamping_case_sent' => 'visa_case_submission',
      'visa_issued_or_rejected' => 'visa_decision',
      'protection_call' => 'protection_call',
      'appeared_for_protection' => 'protection_appearance',
      'ticket_handover' => 'ticket_handover',
      'flight_details_uploaded' => 'flight_details',
      'mobilized' => 'mobilization'
    }.freeze

    DOCUMENT_STAGES = %w[registered documents_pending documents_uploaded under_verification verified].freeze

    # Enrolled, Document Submission, Medical and Mobilization Fee: the fee is
    # paid once the candidate is medically fit, before any visa step starts.
    STANDARD_OPENING = DOCUMENT_STAGES + %w[campaign_nomination medical_pending medical_completed fee_pending fee_paid]

    # Protection, Pre Flight Brief and Ready to Fly.
    DEPARTURE_STAGES = %w[appeared_for_protection ticket_handover flight_details_uploaded mobilized].freeze

    # The UAE/Oman flow, also used by the common process.
    STANDARD_STAGES = (STANDARD_OPENING + %w[visa_processing visa_issued_or_rejected] + DEPARTURE_STAGES).freeze

    ALL = [
      {
        code: 'common_mobilization',
        version: 1,
        country_code: nil,
        provisional: true,
        stages: DOCUMENT_STAGES + %w[
          campaign_nomination medical_pending medical_completed fee_pending fee_paid
          visa_processing visa_issued_or_rejected appeared_for_protection ticket_handover
        ]
      },
      {
        code: 'ksa_mobilization',
        version: 1,
        country_code: 'saudi_arabia',
        provisional: false,
        stages: DOCUMENT_STAGES + %w[
          campaign_nomination gamca_medical_pending gamca_medical_completed
          e_number_processing e_number_requested e_number_received biometric_completed
          visa_stamping_case_prepared fee_pending fee_paid visa_stamping_case_sent
          visa_issued_or_rejected appeared_for_protection ticket_handover
        ]
      },
      {
        code: 'qatar_mobilization',
        version: 1,
        country_code: 'qatar',
        provisional: false,
        stages: DOCUMENT_STAGES + %w[
          campaign_nomination medical_appointment medical_fit fee_pending fee_paid
          documents_shared_with_qatar_bu qvc_appointment_booked qvc_completed_outcome_received
          visa_issued_or_rejected protection_call appeared_for_protection ticket_handover
          flight_details_uploaded mobilized
        ]
      },
      # Finalized flows. Each later version retires the earlier one for its
      # country (or the common slot) when seeded.
      { code: 'common_mobilization', version: 2, country_code: nil, provisional: true, stages: STANDARD_STAGES },
      {
        code: 'ksa_mobilization',
        version: 2,
        country_code: 'saudi_arabia',
        provisional: false,
        # Mobilization Fee before Tasheer registration (e-number, biometric,
        # visa stamping case), as in the client's KSA flow.
        stages: DOCUMENT_STAGES + %w[
          campaign_nomination gamca_medical_pending gamca_medical_completed fee_pending fee_paid
          e_number_processing e_number_requested e_number_received biometric_completed
          visa_stamping_case_prepared visa_stamping_case_sent visa_issued_or_rejected
        ] + DEPARTURE_STAGES
      },
      { code: 'uae_mobilization', version: 1, country_code: 'uae', provisional: false, stages: STANDARD_STAGES },
      { code: 'oman_mobilization', version: 1, country_code: 'oman', provisional: false, stages: STANDARD_STAGES }
    ].freeze

    module_function

    def action_type_for(stage_code) = ACTION_TYPES.fetch(stage_code)
  end
end
