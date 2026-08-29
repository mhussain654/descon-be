# frozen_string_literal: true

module CandidateWorkflows
  class PrerequisiteValidator < ApplicationService
    def initialize(candidate:, assignment:, destination_stage:, evidence:)
      @candidate = candidate
      @assignment = assignment
      @destination_stage = destination_stage
      @evidence = evidence
    end

    def call
      case @destination_stage.code
      when 'documents_uploaded'
        documents_uploaded_ready?
      when 'verified'
        all_required_documents_verified?
      when 'fee_paid'
        authoritative_payment_record?
      else
        evidence_present?
      end
    end

    def field
      required_field = TransitionService.required_fields_for(@destination_stage.code).first
      return 'candidate_workflow_transition.to_stage_code' if required_field.blank?

      "candidate_workflow_transition.evidence.#{required_field}"
    end

    private

    def documents_uploaded_ready?
      progress = Candidates::ApplicationProgress::SummaryService.call(candidate: @candidate, assignment: @assignment)

      progress.documents.required_total.positive? &&
        progress.documents.blocking_requirements.empty? &&
        progress.documents.submitted_total == progress.documents.required_total
    end

    def all_required_documents_verified?
      required_requirements = Candidates::Documents::RequirementResolver.call(
        candidate: @candidate,
        assignment: @assignment
      ).select(&:required)
      return false if required_requirements.empty?

      documents_by_type = current_documents(required_requirements)
      required_requirements.all? { |requirement| verified_requirement?(requirement, documents_by_type) }
    end

    def current_documents(required_requirements)
      @assignment
        .candidate_documents
        .current_version
        .where(document_type_id: required_requirements.map(&:document_type_id))
        .index_by(&:document_type_id)
    end

    def verified_requirement?(requirement, documents_by_type)
      document = documents_by_type[requirement.document_type_id]
      return false unless document&.api_status == 'verified'
      return true unless requirement.document_type.code == CandidateDocument::PCC_REQUIREMENT_CODE

      document.compliance_status != 'expired'
    end

    def authoritative_payment_record?
      @assignment.payments.where(status_code: 'paid').where.not(paid_at: nil).exists?
    end

    def evidence_present?
      required_fields = TransitionService.required_fields_for(@destination_stage.code)
      return true if required_fields.empty?

      required_fields.all? { |field_name| @evidence[field_name].present? }
    end
  end
end
