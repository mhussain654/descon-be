# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::DocumentSubmissions::SubmissionAuditMetadataBuilder do
  it 'builds pii-safe submission audit metadata' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    submission = create(:candidate_document_submission, candidate_assignment: assignment)

    metadata = described_class.call(
      candidate:,
      current_assignment: assignment,
      required_requirements: [],
      submission:,
      submitted_documents: []
    )

    expect(metadata).to include(
      candidate_public_id: candidate.public_id,
      candidate_assignment_public_id: assignment.public_id,
      submission_public_id: submission.public_id,
      submitted_requirement_codes: []
    )
  end
end
