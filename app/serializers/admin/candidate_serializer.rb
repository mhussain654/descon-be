# frozen_string_literal: true

module Admin
  # Full, unmasked staff-facing candidate detail -- distinct from
  # Candidates::ProfileSerializer (the candidate's own self-service view,
  # which masks the CNIC and omits mobile/passport). Staff with
  # view_candidates/manage_candidates are trusted with the real values.
  class CandidateSerializer
    # `include_profile_photo`: only the single-candidate view carries the photo
    # (a signed link per row would cost the list a query per candidate).
    def initialize(candidate, include_profile_photo: false)
      @candidate = candidate
      @include_profile_photo = include_profile_photo
    end

    def as_json(*)
      json = candidate_attributes.merge(updated_at: candidate_updated_at, assignment: serialized_assignment)
      json[:profile_photo] = ::Admin::CandidateProfilePhotoSerializer.new(@candidate).as_json if @include_profile_photo
      json
    end

    private

    def candidate_attributes
      {
        id: @candidate.public_id,
        full_name: @candidate.full_name,
        cnic: @candidate.cnic,
        mobile_number: @candidate.mobile_number,
        passport_number: @candidate.passport_number
      }.merge(next_of_kin_attributes).merge(candidate_status_attributes)
    end

    def next_of_kin_attributes
      {
        next_of_kin_name: @candidate.next_of_kin_name,
        next_of_kin_relationship: @candidate.next_of_kin_relationship,
        next_of_kin_mobile_number: @candidate.next_of_kin_mobile_number,
        next_of_kin_cnic: @candidate.next_of_kin_cnic,
        preferred_locale: @candidate.preferred_locale
      }
    end

    def candidate_status_attributes
      {
        candidate_status: @candidate.status_code,
        active: @candidate.active,
        created_at: @candidate.created_at.utc.iso8601
      }
    end

    def candidate_updated_at
      [@candidate.updated_at, assignment&.updated_at].compact.max&.utc&.iso8601
    end

    def assignment
      @assignment ||= @candidate.current_assignment
    end

    def serialized_assignment
      return if assignment.blank?

      assignment_attributes.merge(
        country: reference(assignment.country),
        project: reference(assignment.project),
        craft: reference(assignment.craft),
        current_workflow_stage: reference(assignment.current_workflow_stage)
      )
    end

    def assignment_attributes
      {
        id: assignment.public_id,
        reference_number: assignment.reference_number,
        created_at: assignment.created_at.utc.iso8601,
        fields_editable: ::Admin::Candidates::UpdateService.assignment_fields_editable?(assignment)
      }
    end

    def reference(record)
      { code: record.code, name: record.name_for }
    end
  end
end
