# frozen_string_literal: true

module PaymentWorkflowHelpers
  def stage_for(code)
    WorkflowStage.find_by!(code:)
  end

  def create_requirement(assignment:, code: 'passport', required: true)
    document_type = payment_document_type_for(code)

    create(
      :document_requirement,
      document_type:,
      country: assignment.country,
      project: assignment.project,
      craft: assignment.craft,
      required:
    )

    document_type
  end

  def create_verified_requirement(assignment:, code: 'passport')
    document_type = create_requirement(assignment:, code:)
    create(
      :candidate_document,
      candidate_assignment: assignment,
      document_type:,
      status_code: 'verified',
      verified_by: create(:user, role: 'admin'),
      verified_at: Time.current
    )
  end

  def create_all_verified_required_documents(assignment:)
    create_verified_requirement(assignment:, code: 'passport')

    required_requirements_for(assignment).each do |requirement|
      next if current_document_exists?(assignment:, requirement:)

      create_verified_document(assignment:, requirement:)
    end
  end

  private

  def payment_document_type_for(code)
    DocumentType.find_or_create_by!(code:) do |record|
      record.name_en = code.humanize
      record.name_ur = code.humanize
      record.active = true
      record.requires_number = false
      record.requires_expiry = false
    end
  end

  def required_requirements_for(assignment)
    Candidates::Documents::RequirementResolver.call(
      candidate: assignment.candidate,
      assignment:
    ).select(&:required)
  end

  def current_document_exists?(assignment:, requirement:)
    assignment.candidate_documents.current_version.exists?(document_type_id: requirement.document_type_id)
  end

  def create_verified_document(assignment:, requirement:)
    create(
      :candidate_document,
      candidate_assignment: assignment,
      document_type: requirement.document_type,
      status_code: 'verified',
      verified_by: create(:user, role: 'admin'),
      verified_at: Time.current
    )
  end
end

RSpec.configure do |config|
  config.include PaymentWorkflowHelpers, type: :request
end
