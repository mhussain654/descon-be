# frozen_string_literal: true

module DocumentRequirementHelpers
  # Some document types (currently only the Police Character Certificate,
  # a global required document since
  # db/migrate/20260912100000_activate_missing_global_document_requirements.rb)
  # require `issued_on` to be present -- see
  # CandidateDocuments::PoliceCharacterCompliance. Generic "create every
  # currently-required document" test helpers call this so they build a
  # valid fixture without needing to know about PCC-specific validation.
  def compliance_attributes_for(document_type)
    return {} unless document_type.code == CandidateDocuments::PoliceCharacterCompliance::PCC_REQUIREMENT_CODE

    { issued_on: Date.current }
  end
end

RSpec.configure do |config|
  config.include DocumentRequirementHelpers
end
