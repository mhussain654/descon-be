# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateWorkflows::TransitionService do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  def stage_for(code)
    WorkflowStage.find_by!(code:)
  end

  def requirement_for(assignment:, code:, required: true)
    document_type = document_type_for(code)
    create_requirement_record(assignment:, document_type:, required:)
    document_type
  end

  def document_type_for(code)
    DocumentType.find_or_create_by!(code:) do |record|
      record.name_en = code.humanize
      record.name_ur = code.humanize
      record.active = true
      record.requires_number = false
      record.requires_expiry = false
    end
  end

  def create_requirement_record(assignment:, document_type:, required:)
    create(
      :document_requirement,
      document_type:,
      country: assignment.country,
      project: assignment.project,
      craft: assignment.craft,
      required:
    )
  end

  def create_verified_required_document(assignment:, code:)
    document_type = requirement_for(assignment:, code:)
    create(
      :candidate_document,
      candidate_assignment: assignment,
      document_type:,
      status_code: 'verified',
      verified_by: create(:user, role: 'admin'),
      verified_at: Time.current
    )
  end

  def create_uploaded_required_document(assignment:, code:)
    document_type = requirement_for(assignment:, code:)
    create(:candidate_document, candidate_assignment: assignment, document_type:, status_code: 'uploaded')
  end

  def resolved_required_requirements(candidate:, assignment:)
    Candidates::Documents::RequirementResolver.call(candidate:, assignment:).select(&:required)
  end

  def create_required_documents(candidate:, assignment:, default_status:, overrides: {})
    resolved_required_requirements(candidate:, assignment:).each do |requirement|
      create_required_document(
        assignment:,
        requirement:,
        default_status:,
        overrides: overrides.fetch(requirement.document_type.code, {})
      )
    end
  end

  def create_required_document(assignment:, requirement:, default_status:, overrides:)
    override_attributes = overrides.dup
    return if override_attributes.delete(:skip_create)

    status_code = override_attributes.fetch(:status_code, default_status)
    attributes = {
      candidate_assignment: assignment,
      document_type: requirement.document_type,
      status_code:
    }.merge(default_status_attributes_for(status_code)).merge(override_attributes)

    create(:candidate_document, **attributes)
  end

  def default_status_attributes_for(status_code)
    return {} unless status_code == 'verified'

    { verified_by: create(:user, role: 'admin'), verified_at: Time.current }
  end

  def transition!(candidate:, actor:, to_stage_code:, **)
    described_class.call(
      actor:,
      candidate:,
      to_stage_code:,
      request_id: SecureRandom.uuid,
      **
    )
  end

  def expect_validation_error(field:)
    yield
    raise 'Expected ValidationError to be raised'
  rescue ValidationError => e
    expect(e.field).to eq(field)
  end

  it 'progresses through the complete 15-stage workflow without skipping stages' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('registered'))

    transition!(candidate:, actor:, to_stage_code: 'documents_pending')
    create_uploaded_required_document(assignment:, code: 'passport')
    create_required_documents(
      candidate:,
      assignment:,
      default_status: 'uploaded',
      overrides: {
        'passport' => { skip_create: true }
      }
    )
    transition!(candidate:, actor:, to_stage_code: 'documents_uploaded')
    transition!(candidate:, actor:, to_stage_code: 'under_verification')
    CandidateDocument.current_version.where(candidate_assignment: assignment).find_each do |document|
      document.update!(status_code: 'verified', verified_by: actor, verified_at: Time.current)
    end
    transition!(candidate:, actor:, to_stage_code: 'verified')
    transition!(candidate:, actor:, to_stage_code: 'fee_pending')
    create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'paid',
      paid_at: Time.current,
      external_reference: 'PAY-123'
    )
    transition!(candidate:, actor:, to_stage_code: 'fee_paid')
    transition!(candidate:, actor:, to_stage_code: 'documents_shared_with_qatar_bu')
    transition!(
      candidate:,
      actor:,
      to_stage_code: 'qvc_appointment_booked',
      evidence: { appointment_date: '2026-09-01' }
    )
    transition!(
      candidate:,
      actor:,
      to_stage_code: 'qvc_completed_outcome_received',
      evidence: { qvc_outcome_code: 'approved' }
    )
    transition!(
      candidate:,
      actor:,
      to_stage_code: 'visa_issued_or_rejected',
      evidence: { visa_outcome_code: 'issued', visa_outcome_date: '2026-09-10' }
    )
    transition!(
      candidate:,
      actor:,
      to_stage_code: 'appeared_for_protection',
      evidence: { appeared_for_protection_on: '2026-09-12' }
    )
    transition!(candidate:, actor:, to_stage_code: 'protected_ready_to_fly', evidence: { protected_on: '2026-09-15' })
    transition!(
      candidate:,
      actor:,
      to_stage_code: 'flight_details_uploaded',
      evidence: {
        airline: 'Qatar Airways',
        flight_reference: 'QR-123',
        sector: 'LHE-DOH',
        flight_date: '2026-09-20T14:30:00Z'
      }
    )
    transition!(candidate:, actor:, to_stage_code: 'mobilized', evidence: { mobilized_on: '2026-09-22' })

    expect(candidate.reload.status_code).to eq('mobilized')
    expect(assignment.reload.current_workflow_stage.code).to eq('mobilized')
    expect(assignment.candidate_stage_histories.order(:occurred_at, :id).count).to eq(14)
    expect(AuditEvent.where(action_code: 'candidate_workflow_transitioned', entity_id: assignment.id).count).to eq(14)
  end

  it 'rejects skipped and backward transitions' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('registered'))

    expect do
      transition!(candidate:, actor:, to_stage_code: 'verified')
    end.to raise_error(InvalidWorkflowTransitionError)

    assignment.update!(current_workflow_stage: stage_for('documents_pending'))

    expect do
      transition!(candidate:, actor:, to_stage_code: 'registered')
    end.to raise_error(InvalidWorkflowTransitionError)
  end

  it 'rejects an invalid destination stage code' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('registered'))

    expect do
      transition!(candidate:, actor:, to_stage_code: 'not_a_stage')
    end.to raise_error(InvalidWorkflowTransitionError)
  end

  it 'rejects unauthorized and inactive staff members' do
    candidate = create(:candidate)
    create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('registered'))

    expect do
      transition!(candidate:, actor: create(:user, role: 'hr'), to_stage_code: 'documents_pending')
    end.to raise_error(ForbiddenError)

    expect do
      transition!(candidate:, actor: create(:user, role: 'mps', active: false, staff_state: 'suspended'),
                  to_stage_code: 'documents_pending')
    end.to raise_error(InactiveAccountError)
  end

  it 'rejects inactive candidates' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, active: false)
    create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('registered'))

    expect do
      transition!(candidate:, actor:, to_stage_code: 'documents_pending')
    end.to raise_error(InactiveAccountError)
  end

  it 'requires authoritative prerequisites and evidence dates' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('documents_pending'))

    expect do
      transition!(candidate:, actor:, to_stage_code: 'documents_uploaded')
    end.to raise_error(WorkflowTransitionPrerequisiteError)

    assignment.update!(current_workflow_stage: stage_for('documents_shared_with_qatar_bu'))

    expect do
      transition!(candidate:, actor:, to_stage_code: 'qvc_appointment_booked')
    end.to raise_error(WorkflowTransitionPrerequisiteError)
  end

  it 'detects stale current-stage expectations' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('documents_pending'))

    expect do
      transition!(
        candidate:,
        actor:,
        to_stage_code: 'documents_uploaded',
        expected_current_stage_code: 'registered'
      )
    end.to raise_error(WorkflowTransitionStaleError)
  end

  it 'stores every supported qvc result in history only and does not auto-select a later stage' do
    actor = create(:user, role: 'mps')

    CandidateWorkflows::StageRequirements::QVC_OUTCOME_CODES.each do |outcome_code|
      candidate = create(:candidate)
      assignment = create(
        :candidate_assignment,
        candidate:,
        current_workflow_stage: stage_for('qvc_appointment_booked')
      )
      create(
        :candidate_qvc_attempt,
        candidate_assignment: assignment,
        scheduled_by: actor,
        attempt_number: 1,
        appointment_date: Date.new(2026, 9, 1)
      )

      result = transition!(
        candidate:,
        actor:,
        to_stage_code: 'qvc_completed_outcome_received',
        evidence: { qvc_outcome_code: outcome_code }
      )

      attempt = assignment.candidate_qvc_attempts.latest_first.first

      expect(result.fetch(:history_entry).metadata).to eq('qvc_outcome_code' => outcome_code)
      expect(assignment.reload.current_workflow_stage.code).to eq('qvc_completed_outcome_received')
      expect(candidate.reload.status_code).to eq('qvc_completed_outcome_received')
      expect(assignment.qvc_outcome_code).to eq(outcome_code)
      expect(assignment.qvc_outcome_date).to be_present
      expect(attempt.outcome_code).to eq(outcome_code)
      expect(attempt.outcome_recorded_at).to be_present
    end
  end

  it 'rejects unsupported qvc outcomes, malformed dates, and unexpected evidence keys with field-addressable errors' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('qvc_appointment_booked'))
    create(
      :candidate_qvc_attempt,
      candidate_assignment: assignment,
      scheduled_by: actor,
      attempt_number: 1,
      appointment_date: Date.new(2026, 9, 1)
    )

    expect_validation_error(field: 'candidate_workflow_transition.evidence.qvc_outcome_code') do
      transition!(
        candidate:,
        actor:,
        to_stage_code: 'qvc_completed_outcome_received',
        evidence: { qvc_outcome_code: 'failed' }
      )
    end

    expect_validation_error(field: 'candidate_workflow_transition.evidence.passport_number') do
      transition!(
        candidate:,
        actor:,
        to_stage_code: 'qvc_completed_outcome_received',
        evidence: {
          qvc_outcome_code: 'approved',
          passport_number: 'AB123456'
        }
      )
    end

    assignment.update!(current_workflow_stage: stage_for('visa_issued_or_rejected'))
    candidate.update!(status_code: 'visa_issued_or_rejected')
    create(
      :candidate_stage_history,
      candidate_assignment: assignment,
      from_workflow_stage: stage_for('qvc_completed_outcome_received'),
      to_workflow_stage: stage_for('visa_issued_or_rejected'),
      actor:,
      occurred_at: Time.current,
      metadata: { 'visa_outcome_code' => 'issued', 'visa_outcome_date' => '2026-09-10' }
    )

    expect_validation_error(field: 'candidate_workflow_transition.evidence.appeared_for_protection_on') do
      transition!(
        candidate:,
        actor:,
        to_stage_code: 'appeared_for_protection',
        evidence: { appeared_for_protection_on: 'not-a-date' }
      )
    end
  end

  it 'rejects unsupported visa outcomes' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    assignment = create(
      :candidate_assignment,
      candidate:,
      current_workflow_stage: stage_for('qvc_completed_outcome_received')
    )
    create(
      :candidate_qvc_attempt,
      candidate_assignment: assignment,
      scheduled_by: actor,
      attempt_number: 1,
      appointment_date: Date.new(2026, 9, 1),
      outcome_code: 'approved',
      outcome_recorded_at: Time.zone.parse('2026-09-05T10:00:00Z'),
      outcome_recorded_by: actor
    )

    expect_validation_error(field: 'candidate_workflow_transition.evidence.visa_outcome_code') do
      transition!(
        candidate:,
        actor:,
        to_stage_code: 'visa_issued_or_rejected',
        evidence: { visa_outcome_code: 'pending', visa_outcome_date: '2026-09-10' }
      )
    end
  end

  it 'treats mobilized as terminal' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('mobilized'))

    expect do
      transition!(candidate:, actor:, to_stage_code: 'documents_pending')
    end.to raise_error(InvalidWorkflowTransitionError)
  end

  it 'requires an approved qvc outcome before visa progression and a visa-issued result before protection' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'qvc_completed_outcome_received')
    assignment = create(
      :candidate_assignment,
      candidate:,
      current_workflow_stage: stage_for('qvc_completed_outcome_received')
    )

    create(
      :candidate_qvc_attempt,
      candidate_assignment: assignment,
      scheduled_by: actor,
      attempt_number: 1,
      appointment_date: Date.new(2026, 9, 1),
      outcome_code: 're_medical',
      outcome_recorded_at: Time.zone.parse('2026-09-02T10:00:00Z'),
      outcome_recorded_by: actor
    )

    expect do
      transition!(
        candidate:,
        actor:,
        to_stage_code: 'visa_issued_or_rejected',
        evidence: { visa_outcome_code: 'issued', visa_outcome_date: '2026-09-10' }
      )
    end.to raise_error(WorkflowTransitionPrerequisiteError) { |error|
      expect(error.details[:blocking_reasons]).to eq(['qvc_approval_required'])
    }

    assignment.candidate_qvc_attempts.last.update!(
      outcome_code: 'approved',
      outcome_recorded_at: Time.zone.parse('2026-09-03T10:00:00Z'),
      outcome_recorded_by: actor
    )
    assignment.update!(qvc_outcome_code: 'approved', qvc_outcome_date: Date.new(2026, 9, 3))

    transition!(
      candidate:,
      actor:,
      to_stage_code: 'visa_issued_or_rejected',
      evidence: {
        visa_outcome_code: 'rejected',
        visa_outcome_date: '2026-09-10',
        rejection_reason_code: 'document_discrepancy'
      }
    )

    expect do
      transition!(
        candidate:,
        actor:,
        to_stage_code: 'appeared_for_protection',
        evidence: { appeared_for_protection_on: '2026-09-12' }
      )
    end.to raise_error(WorkflowTransitionPrerequisiteError) { |error|
      expect(error.details[:blocking_reasons]).to eq(['visa_issued_required'])
    }
  end

  it 'blocks fee_pending when a previously verified required document is rejected' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'verified')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('verified'))
    requirement_for(assignment:, code: 'passport')
    create_required_documents(candidate:, assignment:, default_status: 'verified')

    rejected_requirement = resolved_required_requirements(candidate:, assignment:).first
    assignment.candidate_documents.current_version.find_by!(document_type: rejected_requirement.document_type).update!(
      status_code: 'rejected',
      rejection_reason: 'Document is unreadable.',
      verified_at: Time.current,
      verified_by: actor
    )

    expect do
      transition!(candidate:, actor:, to_stage_code: 'fee_pending')
    end.to raise_error(WorkflowTransitionPrerequisiteError) { |error|
      expect(error.details[:blocking_reasons]).to eq(['required_documents_not_verified'])
    }
  end

  it 'blocks fee_pending when a new required global requirement is introduced after verification' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'verified')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('verified'))
    requirement_for(assignment:, code: 'passport')
    create_required_documents(candidate:, assignment:, default_status: 'verified')
    medical_clearance_type = document_type_for('medical_clearance')
    create(:document_requirement, document_type: medical_clearance_type, required: true, active: true)

    expect do
      transition!(candidate:, actor:, to_stage_code: 'fee_pending')
    end.to raise_error(WorkflowTransitionPrerequisiteError) { |error|
      expect(error.details[:blocking_reasons]).to eq(['required_documents_not_verified'])
    }
  end

  it 'blocks fee_pending for expired pcc and fee_paid without a full authoritative payment record' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'verified')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('verified'))
    requirement_for(assignment:, code: 'passport')
    pcc_type = requirement_for(assignment:, code: CandidateDocument::PCC_REQUIREMENT_CODE)
    create(
      :candidate_document,
      candidate_assignment: assignment,
      document_type: document_type_for('passport'),
      status_code: 'verified',
      verified_by: actor,
      verified_at: Time.current
    )
    expired_pcc = create(
      :candidate_document,
      candidate_assignment: assignment,
      document_type: pcc_type,
      status_code: 'verified',
      issued_on: Date.new(2026, 1, 1),
      verified_by: actor,
      verified_at: Time.current
    )

    expect(expired_pcc.compliance_status).to eq('expired')

    expect do
      transition!(candidate:, actor:, to_stage_code: 'fee_pending')
    end.to raise_error(WorkflowTransitionPrerequisiteError) { |error|
      expect(error.details[:blocking_reasons]).to eq(['expired_pcc'])
    }

    expired_pcc.update!(
      issued_on: Date.new(2026, 8, 30),
      expires_on: Date.new(2027, 2, 28),
      status_code: 'verified',
      verified_at: Time.current,
      verified_by: actor
    )
    transition!(candidate:, actor:, to_stage_code: 'fee_pending')
    create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'paid',
      paid_at: Time.current,
      external_reference: nil
    )

    expect do
      transition!(candidate:, actor:, to_stage_code: 'fee_paid')
    end.to raise_error(WorkflowTransitionPrerequisiteError) { |error|
      expect(error.details[:blocking_reasons]).to eq(['payment_required'])
    }
  end

  it 'creates exactly one qatar bu sharing event with server-owned reason code and safe payload' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'fee_paid')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_paid'))
    requirement_for(assignment:, code: 'passport')
    create_required_documents(candidate:, assignment:, default_status: 'verified')
    create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'paid',
      paid_at: Time.zone.parse('2026-08-30T08:00:00Z'),
      external_reference: 'PAY-QA-001'
    )

    result = transition!(
      candidate:,
      actor:,
      to_stage_code: 'documents_shared_with_qatar_bu',
      expected_current_stage_code: 'fee_paid',
      reason_code: 'frontend_value_should_not_win'
    )

    history_entry = result.fetch(:history_entry)
    event = CandidateWorkflowEvent.find_by!(candidate_stage_history: history_entry)

    expect(history_entry.reason_code).to eq('qatar_bu_shared')
    expect(event.event_code).to eq('documents_shared_with_qatar_bu_confirmed')
    expect(event.request_id).to be_present
    expect(event.actor).to eq(actor)
    expect(event.occurred_at).to eq(history_entry.occurred_at)
    expect(event.payload).to eq(
      'candidate_public_id' => candidate.public_id,
      'candidate_assignment_public_id' => assignment.public_id,
      'actor_public_id' => actor.public_id,
      'to_stage_code' => 'documents_shared_with_qatar_bu',
      'occurred_at' => history_entry.occurred_at.utc.iso8601
    )
    expect(event.payload.to_json).not_to include(candidate.cnic)
    expect(event.payload.to_json).not_to include('PAY-QA-001')
  end

  it 'blocks qatar bu sharing when mandatory documents are no longer verified or compliant' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'fee_paid')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_paid'))
    requirement_for(assignment:, code: 'passport')
    create_required_documents(candidate:, assignment:, default_status: 'verified')
    create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'paid',
      paid_at: Time.current,
      external_reference: 'PAY-QA-002'
    )
    assignment.candidate_documents.current_version.first.update!(
      status_code: 'rejected',
      rejection_reason: 'Document is unreadable.',
      verified_by: actor,
      verified_at: Time.current
    )

    expect do
      transition!(candidate:, actor:, to_stage_code: 'documents_shared_with_qatar_bu')
    end.to raise_error(WorkflowTransitionPrerequisiteError) { |error|
      expect(error.details[:blocking_reasons]).to eq(['required_documents_not_verified'])
    }

    expect(CandidateWorkflowEvent.count).to eq(0)
  end

  it 'blocks qatar bu sharing when the mandatory pcc is expired' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'fee_paid')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_paid'))
    requirement_for(assignment:, code: 'passport')
    pcc_type = requirement_for(assignment:, code: CandidateDocument::PCC_REQUIREMENT_CODE)
    create(
      :candidate_document,
      candidate_assignment: assignment,
      document_type: document_type_for('passport'),
      status_code: 'verified',
      verified_by: actor,
      verified_at: Time.current
    )
    create(
      :candidate_document,
      candidate_assignment: assignment,
      document_type: pcc_type,
      status_code: 'verified',
      issued_on: Date.new(2026, 1, 1),
      verified_by: actor,
      verified_at: Time.current
    )
    create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'paid',
      paid_at: Time.current,
      external_reference: 'PAY-QA-003'
    )

    expect do
      transition!(candidate:, actor:, to_stage_code: 'documents_shared_with_qatar_bu')
    end.to raise_error(WorkflowTransitionPrerequisiteError) { |error|
      expect(error.details[:blocking_reasons]).to eq(['expired_pcc'])
    }
  end

  it 'rolls back workflow state, history, audit, and qatar bu event creation when event persistence fails' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate, status_code: 'fee_paid')
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('fee_paid'))
    requirement_for(assignment:, code: 'passport')
    create_required_documents(candidate:, assignment:, default_status: 'verified')
    create(
      :payment,
      candidate_assignment: assignment,
      status_code: 'paid',
      paid_at: Time.current,
      external_reference: 'PAY-QA-004'
    )

    allow(CandidateWorkflowEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(CandidateWorkflowEvent.new))

    expect do
      transition!(candidate:, actor:, to_stage_code: 'documents_shared_with_qatar_bu')
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(candidate.reload.status_code).to eq('fee_paid')
    expect(assignment.reload.current_workflow_stage.code).to eq('fee_paid')
    expect(
      assignment.candidate_stage_histories.where(to_workflow_stage: stage_for('documents_shared_with_qatar_bu'))
    ).to be_empty
    expect(
      AuditEvent.where(action_code: 'candidate_workflow_transitioned', reason_code: 'qatar_bu_shared')
    ).to be_empty
    expect(CandidateWorkflowEvent.count).to eq(0)
  end

  it 'creates immutable history and rolls back assignment changes when audit creation fails' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('registered'))

    allow(AuditEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditEvent.new))

    expect do
      transition!(candidate:, actor:, to_stage_code: 'documents_pending')
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(candidate.reload.status_code).to eq('registered')
    expect(assignment.reload.current_workflow_stage.code).to eq('registered')
    expect(assignment.candidate_stage_histories).to be_empty
  end
end
