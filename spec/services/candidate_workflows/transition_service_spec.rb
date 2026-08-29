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
    transition!(candidate:, actor:, to_stage_code: 'documents_uploaded')
    transition!(candidate:, actor:, to_stage_code: 'under_verification')
    CandidateDocument.current_version.where(candidate_assignment: assignment).find_each do |document|
      document.update!(status_code: 'verified', verified_by: actor, verified_at: Time.current)
    end
    transition!(candidate:, actor:, to_stage_code: 'verified')
    transition!(candidate:, actor:, to_stage_code: 'fee_pending')
    create(:payment, candidate_assignment: assignment, status_code: 'paid', paid_at: Time.current)
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
      evidence: { qvc_outcome_code: 'approved', qvc_outcome_date: '2026-09-05' }
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
      evidence: { flight_reference: 'QR-123', flight_date: '2026-09-20' }
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

      result = transition!(
        candidate:,
        actor:,
        to_stage_code: 'qvc_completed_outcome_received',
        evidence: { qvc_outcome_code: outcome_code, qvc_outcome_date: '2026-09-05' }
      )

      expect(result.fetch(:history_entry).metadata).to eq(
        'qvc_outcome_code' => outcome_code,
        'qvc_outcome_date' => '2026-09-05'
      )
      expect(assignment.reload.current_workflow_stage.code).to eq('qvc_completed_outcome_received')
      expect(candidate.reload.status_code).to eq('qvc_completed_outcome_received')
      expect(assignment.qvc_outcome_code).to be_nil
      expect(assignment.qvc_outcome_date).to be_nil
    end
  end

  it 'rejects unsupported qvc outcomes, malformed dates, and unexpected evidence keys with field-addressable errors' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('qvc_appointment_booked'))

    expect_validation_error(field: 'candidate_workflow_transition.evidence.qvc_outcome_code') do
      transition!(
        candidate:,
        actor:,
        to_stage_code: 'qvc_completed_outcome_received',
        evidence: { qvc_outcome_code: 'failed', qvc_outcome_date: '2026-09-05' }
      )
    end

    expect_validation_error(field: 'candidate_workflow_transition.evidence.qvc_outcome_date') do
      transition!(
        candidate:,
        actor:,
        to_stage_code: 'qvc_completed_outcome_received',
        evidence: { qvc_outcome_code: 'approved', qvc_outcome_date: 'not-a-date' }
      )
    end

    expect_validation_error(field: 'candidate_workflow_transition.evidence.passport_number') do
      transition!(
        candidate:,
        actor:,
        to_stage_code: 'qvc_completed_outcome_received',
        evidence: {
          qvc_outcome_code: 'approved',
          qvc_outcome_date: '2026-09-05',
          passport_number: 'AB123456'
        }
      )
    end
  end

  it 'rejects unsupported visa outcomes' do
    actor = create(:user, role: 'mps')
    candidate = create(:candidate)
    create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('qvc_completed_outcome_received'))

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
