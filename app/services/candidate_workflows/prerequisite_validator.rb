# frozen_string_literal: true

module CandidateWorkflows
  STAGE_RESULT_METHODS = {
    'documents_uploaded' => :documents_uploaded_result,
    'under_verification' => :documents_uploaded_result,
    'fee_pending' => :verified_documents_result,
    'verified' => :verified_documents_result,
    'fee_paid' => :fee_paid_result,
    'documents_shared_with_qatar_bu' => :qatar_bu_sharing_result,
    'visa_stamping_case_sent' => :paid_with_evidence_result,
    'visa_issued_or_rejected' => :visa_decision_result
  }.freeze

  # Decides whether a candidate may move into `destination_stage`: its evidence
  # must be valid, the stage they're leaving must not be holding them (an
  # outcome stage whose latest decision is unfit/rejected), and the
  # destination's own prerequisites must be met.
  # rubocop:disable Metrics/ClassLength
  class PrerequisiteValidator < ApplicationService
    # The outcome a candidate needs before leaving a stage of this action type.
    OUTCOME_GATES = {
      'medical_outcome' => :medical_fit_gate,
      'visa_decision' => :visa_issued_gate
    }.freeze

    def initialize(candidate:, assignment:, destination_stage:, evidence:)
      @candidate = candidate
      @assignment = assignment
      @destination_stage = destination_stage
      @evidence = evidence
    end

    def call
      EvidenceValidator.call(destination_stage: @destination_stage, evidence: @evidence)

      gate_result = outcome_gate_result
      return gate_result unless gate_result.allowed

      stage_result
    end

    private

    # A negative outcome holds the candidate at their outcome stage until staff
    # record a new, positive decision there.
    def outcome_gate_result
      gate = OUTCOME_GATES[@assignment.current_mobilization_process_stage&.action_type]
      gate ? send(gate) : allowed_result
    end

    def medical_fit_gate
      return allowed_result if latest_medical_result&.fit?

      blocked_result(field: 'candidate_workflow_transition.to_stage_code', blocking_reasons: ['medical_fit_required'])
    end

    def visa_issued_gate
      return allowed_result if latest_visa_decision&.issued?

      blocked_result(field: 'candidate_workflow_transition.to_stage_code', blocking_reasons: ['visa_issued_required'])
    end

    def stage_result
      send(::CandidateWorkflows::STAGE_RESULT_METHODS.fetch(@destination_stage.code, :evidence_result))
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

      requirements_not_verified_result(required_requirements:, documents_by_type:)
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

    def requirements_not_verified_result(required_requirements: required_requirements_for_verification,
                                         documents_by_type: current_documents(required_requirements))
      blocking_reason =
        if expired_required_pcc?(required_requirements, documents_by_type)
          'expired_pcc'
        else
          'required_documents_not_verified'
        end

      blocked_result(
        field: 'candidate_workflow_transition.to_stage_code',
        blocking_reasons: [blocking_reason]
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

    def expired_required_pcc?(required_requirements, documents_by_type)
      required_requirements.any? do |requirement|
        requirement.document_type.code == CandidateDocument::PCC_REQUIREMENT_CODE &&
          documents_by_type[requirement.document_type_id]&.compliance_status == 'expired'
      end
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

    def qvc_approved_result
      latest_attempt = latest_completed_qvc_attempt

      return missing_qvc_approval_result if latest_attempt.blank?
      return rejected_qvc_result if latest_attempt.outcome_code == 'rejected'
      return allowed_with_evidence_result if latest_attempt.outcome_code == 'approved'

      missing_qvc_approval_result
    end

    # Every process requires the fee to be paid before a visa decision; QVC
    # approval is required too where the process has a QVC step (Qatar).
    def visa_decision_result
      paid = payment_result
      return paid unless paid.allowed

      qvc_process? ? qvc_approved_result : evidence_result
    end

    # Qatar BU receives a candidate's file only once documents are verified,
    # the fee is paid and the candidate is medically fit.
    def qatar_bu_sharing_result
      fee_result = fee_paid_result
      return fee_result unless fee_result.allowed

      medical_fit_gate
    end

    def paid_with_evidence_result
      paid = payment_result
      paid.allowed ? evidence_result : paid
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

    def allowed_with_evidence_result
      evidence_fields = TransitionService.required_fields_for(@destination_stage.code)
      return allowed_result if evidence_fields.empty?

      evidence_result
    end

    def latest_completed_qvc_attempt
      @latest_completed_qvc_attempt ||= completed_qvc_attempts_scope.first
    end

    def completed_qvc_attempts_scope
      @assignment.candidate_qvc_attempts.where.not(outcome_recorded_at: nil).latest_first
    end

    def latest_visa_decision
      @latest_visa_decision ||= @assignment.candidate_visa_decisions.latest_first.first
    end

    def latest_medical_result
      @latest_medical_result ||= @assignment.candidate_medical_results.latest_first.first
    end

    def qvc_process?
      @assignment.mobilization_process.includes_stage_code?('qvc_completed_outcome_received')
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

    def missing_qvc_approval_result
      blocked_result(
        field: 'candidate_workflow_transition.to_stage_code',
        blocking_reasons: ['qvc_approval_required']
      )
    end

    def rejected_qvc_result
      blocked_result(
        field: 'candidate_workflow_transition.to_stage_code',
        blocking_reasons: ['qvc_rejected']
      )
    end
  end
  # rubocop:enable Metrics/ClassLength
end
