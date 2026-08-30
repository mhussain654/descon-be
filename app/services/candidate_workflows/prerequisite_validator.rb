# frozen_string_literal: true

module CandidateWorkflows
  # rubocop:disable Metrics/ClassLength
  class PrerequisiteValidator < ApplicationService
    def initialize(candidate:, assignment:, destination_stage:, evidence:)
      @candidate = candidate
      @assignment = assignment
      @destination_stage = destination_stage
      @evidence = evidence
    end

    def call
      EvidenceValidator.call(destination_stage: @destination_stage, evidence: @evidence)

      stage_result
    end

    private

    def stage_result
      case @destination_stage.code
      when 'documents_uploaded'
        documents_uploaded_result
      when 'fee_pending', 'verified'
        verified_documents_result
      when 'fee_paid'
        fee_paid_result
      else
        evidence_result
      end
    end

    def documents_uploaded_result
      progress = Candidates::ApplicationProgress::SummaryService.call(candidate: @candidate, assignment: @assignment)
      documents_ready =
        progress.documents.required_total.positive? &&
        progress.documents.blocking_requirements.empty? &&
        progress.documents.submitted_total == progress.documents.required_total

      return allowed_result if documents_ready

      blocked_result(field: 'candidate_workflow_transition.to_stage_code', blocking_reasons: ['documents_required'])
    end

    def verified_documents_result
      required_requirements = required_requirements_for_verification
      return requirements_not_verified_result if required_requirements.empty?

      documents_by_type = current_documents(required_requirements)
      return allowed_result if requirements_verified?(required_requirements, documents_by_type)

      requirements_not_verified_result
    end

    def required_requirements_for_verification
      Candidates::Documents::RequirementResolver.call(
        candidate: @candidate,
        assignment: @assignment
      ).select(&:required)
    end

    def requirements_verified?(required_requirements, documents_by_type)
      required_requirements.all? { |requirement| verified_requirement?(requirement, documents_by_type) }
    end

    def requirements_not_verified_result
      blocked_result(
        field: 'candidate_workflow_transition.to_stage_code',
        blocking_reasons: ['required_documents_not_verified']
      )
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

    def fee_paid_result
      verification_result = verified_documents_result
      return verification_result unless verification_result.allowed

      payment_result
    end

    def payment_result
      payments = @assignment.payments.where(status_code: 'paid')
      payment_record_exists = payments.where.not(paid_at: nil).where.not(external_reference: nil).exists?
      return allowed_result if payment_record_exists

      blocked_result(field: 'candidate_workflow_transition.to_stage_code', blocking_reasons: ['payment_required'])
    end

    def evidence_result
      required_fields = TransitionService.required_fields_for(@destination_stage.code)
      return allowed_result if required_fields.empty?

      missing_field = required_fields.find { |field_name| @evidence[field_name].blank? }
      return allowed_result if missing_field.blank?

      blocked_result(
        field: evidence_field(missing_field),
        required_fields: required_fields,
        blocking_reasons: [StageRequirements.field_required_blocking_reason(missing_field)]
      )
    end

    def evidence_field(field_name)
      "candidate_workflow_transition.evidence.#{field_name}"
    end

    def allowed_result
      PrerequisiteResult.allowed(required_fields: TransitionService.required_fields_for(@destination_stage.code))
    end

    def blocked_result(
      field:,
      blocking_reasons:,
      required_fields: TransitionService.required_fields_for(@destination_stage.code)
    )
      PrerequisiteResult.blocked(field:, blocking_reasons:, required_fields:)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
