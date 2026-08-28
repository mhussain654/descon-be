# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::DocumentReviews::SubmissionSummaryBuilder do
  def create_submission_with_documents(status_codes)
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    submission = create(:candidate_document_submission, candidate_assignment: assignment)

    status_codes.each_with_index do |status_code, index|
      create_submission_item(submission:, assignment:, status_code:, index:)
    end

    submission
  end

  def create_submission_item(submission:, assignment:, status_code:, index:)
    document_type = create(:document_type, code: "summary_doc_#{SecureRandom.hex(4)}")
    document = create_candidate_document(assignment:, document_type:, status_code:)
    create(
      :candidate_document_submission_item,
      candidate_document_submission: submission,
      candidate_document: document,
      requirement_code: "doc_#{index}",
      required: true
    )
  end

  def create_candidate_document(assignment:, document_type:, status_code:)
    create(
      :candidate_document,
      candidate_assignment: assignment,
      document_type:,
      status_code:,
      **review_metadata(status_code)
    )
  end

  def review_metadata(status_code)
    if %w[uploaded under_verification].include?(status_code)
      return { verified_by: nil, verified_at: nil, rejection_reason: nil }
    end

    {
      verified_by: create(:user),
      verified_at: Time.current,
      rejection_reason: status_code == 'rejected' ? 'Document is unreadable.' : nil
    }
  end

  it 'derives pending, partially reviewed, changes required, and verified states from required documents' do
    pending = create_submission_with_documents(%w[under_verification])
    partial = create_submission_with_documents(%w[under_verification verified])
    changes_required = create_submission_with_documents(%w[rejected verified])
    verified = create_submission_with_documents(%w[verified verified])

    expect(described_class.call(submission: pending).review_state).to eq('pending_review')
    expect(described_class.call(submission: partial).review_state).to eq('partially_reviewed')
    expect(described_class.call(submission: changes_required).review_state).to eq('changes_required')
    expect(described_class.call(submission: verified).review_state).to eq('verified')
  end
end
