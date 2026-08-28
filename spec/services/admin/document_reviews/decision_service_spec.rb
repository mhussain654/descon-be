# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::DocumentReviews::DecisionService do
  self.use_transactional_tests = false

  around do |example|
    CandidateDocumentSubmissionItem.delete_all
    CandidateDocumentSubmission.delete_all
    AuditEvent.delete_all
    CandidateDocument.delete_all
    CandidateAssignment.delete_all
    Candidate.delete_all
    User.delete_all
    example.run
  ensure
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

  def reviewable_document
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    document = create(:candidate_document, candidate_assignment: assignment, status_code: 'under_verification')
    submission = create(:candidate_document_submission, candidate_assignment: assignment)
    create(:candidate_document_submission_item, candidate_document_submission: submission, candidate_document: document)
    document
  end

  it 'verifies a pending current document atomically and returns updated submission summary' do
    actor = create(:user, role: 'admin')
    document = reviewable_document

    result = described_class.call(actor:, decision: 'verified', document:, request_id: 'review-verify-1')

    expect(result.document.reload.status_code).to eq('verified')
    expect(result.document.verified_by).to eq(actor)
    expect(result.summary.review_state).to eq('verified')
    expect(AuditEvent.last.action_code).to eq('candidate_document_verified')
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
