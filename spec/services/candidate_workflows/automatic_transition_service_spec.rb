# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateWorkflows::AutomaticTransitionService do
  before do
    ensure_canonical_workflow_stages!
  end

  def stage_for(code)
    WorkflowStage.find_by!(code:)
  end

  def resolved_required_requirements(candidate:, assignment:)
    Candidates::Documents::RequirementResolver.call(candidate:, assignment:).select(&:required)
  end

  # rubocop:disable Metrics/MethodLength
  def create_required_documents(candidate:, assignment:, status_code:)
    create_verified_bank_detail(assignment:) if status_code == 'verified'
    resolved_required_requirements(candidate:, assignment:).each do |requirement|
      attributes = {
        **compliance_attributes_for(requirement.document_type),
        candidate_assignment: assignment,
        document_type: requirement.document_type,
        status_code:
      }

      if status_code == 'verified'
        attributes[:verified_by] = create(:user, role: 'admin')
        attributes[:verified_at] = Time.current
      end

      create(:candidate_document, **attributes)
    end
  end
  # rubocop:enable Metrics/MethodLength

  # rubocop:disable Metrics/MethodLength
  def create_requirement(assignment:, code:, required: true)
    document_type = DocumentType.find_or_create_by!(code:) do |record|
      record.name_en = code.humanize
      record.name_ur = code.humanize
      record.active = true
      record.requires_number = false
      record.requires_expiry = false
    end

    create(
      :document_requirement,
      document_type:,
      country: assignment.country,
      project: assignment.project,
      craft: assignment.craft,
      required:
    )
  end
  # rubocop:enable Metrics/MethodLength

  describe '.call' do
    it 'moves a newly assigned candidate into documents_pending' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('registered'))

      described_class.call(candidate:, event: :assignment_created, request_id: 'auto-assignment-1')

      expect(assignment.reload.current_workflow_stage.code).to eq('documents_pending')
      expect(candidate.reload.status_code).to eq('documents_pending')
      expect(assignment.candidate_stage_histories.order(:occurred_at, :id).pluck(:reason_code)).to eq(
        ['auto_assignment_created']
      )
    end

    it 'does not move to documents_uploaded until all mandatory documents are uploaded' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('documents_pending'))
      create_requirement(assignment:, code: 'passport')
      create_requirement(assignment:, code: 'cv')
      first_requirement = resolved_required_requirements(candidate:, assignment:).first
      create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: first_requirement.document_type,
        status_code: 'uploaded'
      )

      described_class.call(candidate:, event: :documents_uploaded, request_id: 'auto-doc-upload-1')

      expect(assignment.reload.current_workflow_stage.code).to eq('documents_pending')
    end

    it 'moves to documents_uploaded when every mandatory document is uploaded' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('documents_pending'))
      create_requirement(assignment:, code: 'passport')
      create_requirement(assignment:, code: 'cv')
      create_required_documents(candidate:, assignment:, status_code: 'uploaded')

      described_class.call(candidate:, event: :documents_uploaded, request_id: 'auto-doc-upload-2')

      expect(assignment.reload.current_workflow_stage.code).to eq('documents_uploaded')
      expect(candidate.reload.status_code).to eq('documents_uploaded')
    end

    it 'ignores optional documents when deciding whether uploads are complete' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('documents_pending'))
      create_requirement(assignment:, code: 'passport')
      optional_type = DocumentType.find_or_create_by!(code: 'portfolio') do |document_type|
        document_type.name_en = 'Portfolio'
        document_type.name_ur = 'پورٹ فولیو'
        document_type.active = true
        document_type.requires_number = false
        document_type.requires_expiry = false
      end
      create(:document_requirement, document_type: optional_type, required: false, active: true)
      create_required_documents(candidate:, assignment:, status_code: 'uploaded')

      described_class.call(candidate:, event: :documents_uploaded, request_id: 'auto-doc-upload-3')

      expect(assignment.reload.current_workflow_stage.code).to eq('documents_uploaded')
    end

    it 'moves to under_verification when all mandatory uploads are submitted' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('documents_uploaded'))
      create_requirement(assignment:, code: 'passport')
      create_required_documents(candidate:, assignment:, status_code: 'under_verification')

      described_class.call(candidate:, event: :documents_submitted, request_id: 'auto-doc-submit-1')

      expect(assignment.reload.current_workflow_stage.code).to eq('under_verification')
      expect(candidate.reload.status_code).to eq('under_verification')
    end

    it 'does not move to verified when any mandatory document is rejected' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('under_verification'))
      create_requirement(assignment:, code: 'passport')
      create_required_documents(candidate:, assignment:, status_code: 'verified')
      first_document = assignment.candidate_documents.current_version.order(:id).first
      first_document.update!(
        status_code: 'rejected',
        verified_by: create(:user, role: 'admin'),
        verified_at: Time.current,
        rejection_reason: 'Document is unreadable.'
      )

      described_class.call(candidate:, event: :documents_reviewed, request_id: 'auto-doc-review-1')

      expect(assignment.reload.current_workflow_stage.code).to eq('under_verification')
    end

    it 'moves through verified to campaign nomination when every mandatory document is approved' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('under_verification'))
      create_requirement(assignment:, code: 'passport')
      create_required_documents(candidate:, assignment:, status_code: 'verified')

      described_class.call(
        candidate:,
        event: :documents_reviewed,
        actor: create(:user, role: 'admin'),
        request_id: 'auto-doc-review-2'
      )

      expect(assignment.reload.current_workflow_stage.code).to eq('campaign_nomination')
      expect(candidate.reload.status_code).to eq('campaign_nomination')
      expect(assignment.candidate_stage_histories.order(:id).last(2).map { |entry| entry.to_workflow_stage.code })
        .to eq(%w[verified campaign_nomination])
    end

    it 'is idempotent when the same event is retried at the already-reached stage' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('documents_pending'))
      create_requirement(assignment:, code: 'passport')
      create_required_documents(candidate:, assignment:, status_code: 'uploaded')

      2.times do
        described_class.call(candidate:, event: :documents_uploaded, request_id: 'auto-doc-upload-4')
      end

      expect(assignment.reload.current_workflow_stage.code).to eq('documents_uploaded')
      expect(assignment.candidate_stage_histories.where(reason_code: 'auto_documents_uploaded').count).to eq(1)
    end

    it 'creates only one transition history row when concurrent events race' do
      candidate = create(:candidate)
      assignment = create(:candidate_assignment, candidate:, current_workflow_stage: stage_for('documents_pending'))
      create_requirement(assignment:, code: 'passport')
      create_required_documents(candidate:, assignment:, status_code: 'uploaded')

      workers = Array.new(2) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.call(candidate:, event: :documents_uploaded, request_id: SecureRandom.uuid)
          end
        end
      end
      workers.each(&:join)

      expect(assignment.reload.current_workflow_stage.code).to eq('documents_uploaded')
      expect(assignment.candidate_stage_histories.where(reason_code: 'auto_documents_uploaded').count).to eq(1)
    end
  end

  describe 'after the fee is paid' do
    def candidate_at_fee_paid(country_code)
      candidate = create(:candidate, status_code: 'fee_paid')
      assignment = create(:candidate_assignment, candidate:, country: process_country(country_code),
                                                 current_workflow_stage: stage_for('fee_paid'))
      [candidate, assignment]
    end

    it 'moves a UAE candidate on to the visa' do
      candidate, assignment = candidate_at_fee_paid(:uae)

      described_class.call(candidate:, event: :fee_paid, request_id: 'auto-fee-uae')

      expect(assignment.reload.current_workflow_stage.code).to eq('visa_processing')
    end

    it 'moves a KSA candidate on to Tasheer registration (e-number processing)' do
      candidate, assignment = candidate_at_fee_paid(:saudi_arabia)

      described_class.call(candidate:, event: :fee_paid, request_id: 'auto-fee-ksa')

      expect(assignment.reload.current_workflow_stage.code).to eq('e_number_processing')
    end

    it 'keeps a paid, medically fit Qatar candidate at Fee Paid until staff confirm the Qatar BU sharing' do
      candidate, assignment = candidate_at_fee_paid(:qatar)
      create_requirement(assignment:, code: 'passport')
      create_required_documents(candidate:, assignment:, status_code: 'verified')
      create(:payment, candidate_assignment: assignment, status_code: 'paid', paid_at: Time.current,
                       external_reference: 'TXN-AUTO-1')
      create(:candidate_medical_result, candidate_assignment: assignment)

      described_class.call(candidate:, event: :fee_paid, request_id: 'auto-fee-qatar')

      expect(assignment.reload.current_workflow_stage.code).to eq('fee_paid')
      expect(assignment.candidate_stage_histories.where(reason_code: 'auto_fee_paid')).not_to exist
    end
  end
end
