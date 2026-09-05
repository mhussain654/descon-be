# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::DocumentReviews::DecisionService do
  self.use_transactional_tests = false

  around do |example|
    AuthenticationEvent.delete_all
    RefreshToken.delete_all
    Session.delete_all
    CandidateStageHistory.delete_all
    CandidateDocumentSubmissionItem.delete_all
    CandidateDocumentSubmission.delete_all
    AuditEvent.delete_all
    CandidateDocument.delete_all
    CandidateAssignment.delete_all
    Candidate.delete_all
    User.delete_all
    example.run
  ensure
    AuthenticationEvent.delete_all
    RefreshToken.delete_all
    Session.delete_all
    CandidateStageHistory.delete_all
    CandidateDocumentSubmissionItem.delete_all
    CandidateDocumentSubmission.delete_all
    AuditEvent.delete_all
    CandidateDocument.delete_all
    CandidateAssignment.delete_all
    Candidate.delete_all
    User.delete_all
  end

  before do
    ensure_staff_authorization_reference_data!
  end

  def resolved_required_requirements(candidate:, assignment:)
    Candidates::Documents::RequirementResolver.call(candidate:, assignment:).select(&:required)
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def reviewable_document
    candidate = create(:candidate)
    assignment = create(
      :candidate_assignment,
      candidate:,
      current_workflow_stage: WorkflowStage.find_by!(code: 'under_verification')
    )
    candidate.update!(status_code: 'under_verification')
    document_type = DocumentType.find_or_create_by!(code: 'passport') do |record|
      record.name_en = 'Passport'
      record.name_ur = 'پاسپورٹ'
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
      required: true
    )
    requirements = resolved_required_requirements(candidate:, assignment:)
    pending_requirement = requirements.first

    requirements.drop(1).each do |requirement|
      create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: requirement.document_type,
        status_code: 'verified',
        verified_by: create(:user),
        verified_at: Time.current
      )
    end

    document = create(
      :candidate_document,
      candidate_assignment: assignment,
      document_type: pending_requirement.document_type,
      status_code: 'under_verification'
    )
    submission = create(:candidate_document_submission, candidate_assignment: assignment)
    create(:candidate_document_submission_item, candidate_document_submission: submission, candidate_document: document)
    document
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  it 'verifies a pending current document atomically and returns updated submission summary' do
    actor = create(:user, role: 'admin')
    document = reviewable_document

    result = described_class.call(actor:, decision: 'verified', document:, request_id: 'review-verify-1')

    expect(result.document.reload.status_code).to eq('verified')
    expect(result.document.verified_by).to eq(actor)
    expect(result.summary.review_state).to eq('verified')
    expect(AuditEvent.where(action_code: 'candidate_document_verified').count).to eq(1)
    expect(document.candidate_assignment.reload.current_workflow_stage.code).to eq('verified')
    expect(document.candidate_assignment.candidate.reload.status_code).to eq('verified')
  end

  it 'applies HR-confirmed issued_on/expires_on when verifying' do
    actor = create(:user, role: 'admin')
    document = reviewable_document

    result = described_class.call(
      actor:, decision: 'verified', document:, request_id: 'review-verify-ocr-1',
      issued_on: '2020-01-01', expires_on: '2030-01-01'
    )

    expect(result.document.reload.issued_on).to eq(Date.new(2020, 1, 1))
    expect(result.document.expires_on).to eq(Date.new(2030, 1, 1))
  end

  it 'never applies issued_on/expires_on when rejecting' do
    actor = create(:user, role: 'admin')
    document = reviewable_document

    described_class.call(
      actor:, decision: 'rejected', document:, rejection_reason: 'Document is unreadable.',
      request_id: 'review-reject-ocr-1', issued_on: '2020-01-01', expires_on: '2030-01-01'
    )

    expect(document.reload.issued_on).to be_nil
    expect(document.expires_on).to be_nil
  end

  it 'leaves issued_on/expires_on untouched when not supplied' do
    actor = create(:user, role: 'admin')
    document = reviewable_document

    described_class.call(actor:, decision: 'verified', document:, request_id: 'review-verify-ocr-2')

    expect(document.reload.issued_on).to be_nil
    expect(document.reload.expires_on).to be_nil
  end

  it 'rejects with a normalized reason and blocks missing or invalid reasons' do
    actor = create(:user, role: 'admin')
    document = reviewable_document

    result = described_class.call(
      actor:,
      decision: 'rejected',
      document:,
      rejection_reason: '  Document is unreadable.  ',
      request_id: 'review-reject-1'
    )

    expect(result.document.reload.status_code).to eq('rejected')
    expect(result.document.rejection_reason).to eq('Document is unreadable.')
    expect(result.summary.review_state).to eq('changes_required')

    expect do
      described_class.call(
        actor:,
        decision: 'rejected',
        document: reviewable_document,
        rejection_reason: 'short',
        request_id: 'review-reject-2'
      )
    end.to raise_error(RejectionReasonInvalidError)
  end

  it 'raises when the document is not pending review or was already reviewed' do
    actor = create(:user, role: 'admin')
    uploaded_document = reviewable_document.tap { |document| document.update!(status_code: 'uploaded') }
    verified_document = reviewable_document.tap do |document|
      document.update!(status_code: 'verified', verified_by: actor, verified_at: Time.current)
    end

    expect do
      described_class.call(actor:, decision: 'verified', document: uploaded_document, request_id: 'review-verify-2')
    end.to raise_error(DocumentNotPendingReviewError)

    expect do
      described_class.call(actor:, decision: 'verified', document: verified_document, request_id: 'review-verify-3')
    end.to raise_error(DocumentAlreadyReviewedError)
  end

  it 'rolls back the review decision when audit creation fails' do
    actor = create(:user, role: 'admin')
    document = reviewable_document

    allow(AuditEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditEvent.new))

    expect do
      described_class.call(actor:, decision: 'verified', document:, request_id: 'review-verify-4')
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(document.reload.status_code).to eq('under_verification')
    expect(document.verified_by).to be_nil
    expect(document.verified_at).to be_nil
  end

  it 'allows only one concurrent decision to succeed' do
    actor = create(:user, role: 'admin')
    document = reviewable_document
    outcomes = Queue.new

    worker = lambda do |decision|
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.call(
          actor:,
          decision:,
          document:,
          request_id: SecureRandom.uuid,
          rejection_reason: 'Document is unreadable.'
        )
        outcomes << decision
      rescue DocumentAlreadyReviewedError
        outcomes << :already_reviewed
      end
    end

    threads = [
      Thread.new { worker.call('verified') },
      Thread.new { worker.call('rejected') }
    ]
    threads.each(&:join)

    expect(Array.new(2) { outcomes.pop }).to include(:already_reviewed)
    expect(document.reload.status_code).to be_in(%w[verified rejected])
    expect(AuditEvent.where(action_code: %w[candidate_document_verified candidate_document_rejected]).count).to eq(1)
  end
end
