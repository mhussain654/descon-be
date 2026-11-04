# frozen_string_literal: true

module StoreReview
  # Creates the store reviewer's demo candidate (StoreReview::Account) on the
  # Qatar flow at Enrolled, with obviously fake details. Unlike the admin
  # form it doesn't move the candidate on to Document Submission. Running it
  # again returns the existing candidate unchanged.
  class CreateCandidateService < ApplicationService
    class NotConfiguredError < StandardError
    end

    FULL_NAME = 'Store Reviewer'
    # Never texted: no SMS is sent for this account.
    MOBILE_NUMBER = '+920000000000'
    REFERENCE_NUMBER = 'STORE-REVIEW'
    COUNTRY_CODE = 'qatar'
    PROJECT_CODE = 'qatar_infrastructure'
    CRAFT_CODE = 'electrician'

    def initialize(created_by:)
      @created_by = created_by
    end

    def call
      raise NotConfiguredError, 'Set store_review cnic and otp_code in the encrypted credentials first.' unless
        Account.enabled?

      Candidate.find_by(cnic: Account.cnic) || create_candidate!
    end

    private

    def create_candidate!
      Candidate.transaction do
        candidate = Candidate.create!(
          full_name: FULL_NAME, cnic: Account.cnic, mobile_number: MOBILE_NUMBER, preferred_locale: 'en',
          source_code: 'admin_ui', status_code: 'registered', created_by: @created_by
        )
        create_assignment!(candidate)
        record_audit!(candidate)
        candidate
      end
    end

    def create_assignment!(candidate)
      candidate.candidate_assignments.create!(
        reference_number: REFERENCE_NUMBER, country: Country.find_by!(code: COUNTRY_CODE),
        project: Project.find_by!(code: PROJECT_CODE), craft: Craft.find_by!(code: CRAFT_CODE),
        current_workflow_stage: WorkflowStage.find_by!(code: 'registered'), created_by: @created_by
      )
    end

    def record_audit!(candidate)
      AuditEvent.create!(
        actor: @created_by, candidate:, entity_type: 'Candidate', entity_id: candidate.id,
        action_code: 'store_review_candidate_created', metadata: { candidate_public_id: candidate.public_id },
        occurred_at: Time.current
      )
    end
  end
end
