# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::DocumentReviews::AccessService do
  before do
    ensure_staff_authorization_reference_data!
  end

  it 'returns a short-lived private access path and audits the access without logging storage details' do
    actor = create(:user, role: 'admin')
    document = create(:candidate_document, status_code: 'under_verification')
    submission = create(:candidate_document_submission, candidate_assignment: document.candidate_assignment)
    create(:candidate_document_submission_item, candidate_document_submission: submission, candidate_document: document)

    result = described_class.call(actor:, document:, request_id: 'doc-access-1')

    expect(result.document).to eq(document)
    expect(result.url).to include('/rails/active_storage/blobs/proxy/')
    expect(result.url).not_to include('/storage/')
    expect(Time.iso8601(result.expires_at)).to be > Time.current

    event = AuditEvent.last
    expect(event.action_code).to eq('candidate_document_accessed')
    expect(event.metadata).to include(
      'actor_public_id' => actor.public_id,
      'document_public_id' => document.public_id
    )
    expect(event.metadata.to_json).not_to include(document.checksum_sha256.to_s)
  end

  it 'rejects documents whose attachment is missing' do
    actor = create(:user, role: 'admin')
    document = create(:candidate_document, status_code: 'under_verification')
    submission = create(:candidate_document_submission, candidate_assignment: document.candidate_assignment)
    create(:candidate_document_submission_item, candidate_document_submission: submission, candidate_document: document)
    document.file.purge

    expect do
      described_class.call(actor:, document:, request_id: 'doc-access-2')
    end.to raise_error(DocumentAttachmentMissingError)
  end
end
