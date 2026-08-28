# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::DocumentSubmissions::SubmissionAuditCreator do
  it 'records a pii-safe candidate document submission audit event' do
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    submission = create(:candidate_document_submission, candidate_assignment: assignment)

    described_class.call(
      candidate:,
      candidate_assignment: assignment,
      submission:,
      request_id: 'candidate-submit-audit-1',
      metadata: { candidate_public_id: candidate.public_id, submitted_requirement_codes: [] }
    )

    event = AuditEvent.last

    expect(event.action_code).to eq('candidate_documents_submitted')
    expect(event.request_id).to eq('candidate-submit-audit-1')
    expect(event.metadata).to include(
      'candidate_public_id' => candidate.public_id,
      'submitted_requirement_codes' => []
    )
  end
end
