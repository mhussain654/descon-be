# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::DocumentReviewQueueQuery do
  def build_submission(review_state:, submitted_at:)
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    submission = create(:candidate_document_submission, candidate_assignment: assignment, submitted_at:)
    statuses_for(review_state).each_with_index do |status_code, index|
      create_submission_item(submission:, assignment:, status_code:, index:)
    end

    submission
  end

  def create_submission_item(submission:, assignment:, status_code:, index:)
    document_type = create(:document_type, code: "queue_doc_#{SecureRandom.hex(4)}")
    document = create_candidate_document(assignment:, document_type:, status_code:)
    create(
      :candidate_document_submission_item,
      candidate_document_submission: submission,
      candidate_document: document,
      requirement_code: "queue_req_#{index}",
      required: true
    )
  end

  def create_candidate_document(assignment:, document_type:, status_code:)
    create(
      :candidate_document,
      candidate_assignment: assignment,
      document_type:,
      status_code:,
      verified_by: %w[verified rejected].include?(status_code) ? create(:user) : nil,
      verified_at: %w[verified rejected].include?(status_code) ? Time.current : nil,
      rejection_reason: status_code == 'rejected' ? 'Document is unreadable.' : nil
    )
  end

  def statuses_for(review_state)
    {
      'pending_review' => %w[under_verification],
      'partially_reviewed' => %w[under_verification verified],
      'changes_required' => %w[rejected],
      'verified' => %w[verified]
    }.fetch(review_state) { raise ArgumentError, "unsupported state: #{review_state}" }
  end

  it 'defaults to waiting review states and supports filtering and pagination' do
    pending = build_submission(review_state: 'pending_review', submitted_at: 3.days.ago)
    partial = build_submission(review_state: 'partially_reviewed', submitted_at: 2.days.ago)
    build_submission(review_state: 'changes_required', submitted_at: 1.day.ago)
    build_submission(review_state: 'verified', submitted_at: Time.current)

    query = described_class.new(
      scope: CandidateDocumentSubmission.all,
      params: ActionController::Parameters.new(
        page: { number: 1, size: 1 },
        filter: { status: 'pending_review,partially_reviewed' }
      )
    )

    result = query.call

    expect(result).to eq([partial])
    expect(query.pagination).to include(page: 1, per_page: 1, total_count: 2, total_pages: 2)
    expect(
      described_class.new(
        scope: CandidateDocumentSubmission.all,
        params: ActionController::Parameters.new(filter: { candidate_public_id: pending.candidate.public_id })
      ).call
    ).to eq([pending])
  end

  it 'rejects malformed status and submitted_at filters' do
    expect do
      described_class.new(
        scope: CandidateDocumentSubmission.all,
        params: ActionController::Parameters.new(filter: { status: 'ghost' })
      ).call
    end.to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('filter.status') }

    expect do
      described_class.new(
        scope: CandidateDocumentSubmission.all,
        params: ActionController::Parameters.new(filter: { submitted_from: 'invalid-date' })
      ).call
    end.to raise_error(InvalidQueryParameterError) { |error| expect(error.field).to eq('filter.submitted_from') }
  end
end
