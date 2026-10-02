# frozen_string_literal: true

module Candidates
  class ProfileSerializer
    def initialize(candidate)
      @candidate = candidate
    end

    def as_json(*)
      profile_attributes.merge(
        country: serialized_country,
        photo_url: ProfilePhotos::UrlBuilder.call(candidate: @candidate),
        current_workflow_stage: serialized_workflow_stage,
        payment: serialized_payment,
        consent: serialized_consent
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

    # The assignment's destination country -- the Business Unit (Qatar, Oman,
    # KSA, UAE...) the candidate is being mobilized for, with a localized name.
    def serialized_country
      country = current_assignment&.country
      return if country.blank?

      { code: country.code, name: country.name_for }
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

    def serialized_consent
      Candidates::ConsentSerializer.new(@candidate).as_json
    end
  end
end
