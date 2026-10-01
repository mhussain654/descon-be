# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::Documents::AccessService do
  it 'returns a short-lived access path defaulting to inline, auditing the access without logging storage details' do
    document = create(:candidate_document)
    submission = create(:candidate_document_submission, candidate_assignment: document.candidate_assignment)
    create(:candidate_document_submission_item, candidate_document_submission: submission, candidate_document: document)
    candidate = document.candidate_assignment.candidate

    result = described_class.call(actor: nil, candidate:, document:, request_id: 'cand-doc-access-1')

    expect(result.document).to eq(document)
    expect(result.url).to include('/rails/active_storage/blobs/proxy/')
    expect(result.url).to include('disposition=inline')
    expect(result.url).not_to include('/storage/')
    expect(Time.iso8601(result.expires_at)).to be > Time.current

    event = AuditEvent.last
    expect(event.action_code).to eq('candidate_document_accessed')
    expect(event.actor).to be_nil
    expect(event.metadata).to include(
      'accessed_by' => 'candidate', 'document_public_id' => document.public_id, 'disposition' => 'inline'
    )
    expect(event.metadata).not_to have_key('actor_public_id')
    expect(event.metadata.to_json).not_to include(document.checksum_sha256.to_s)
  end

  it 'generates an attachment-disposition URL that prompts a device download when requested' do
    document = create(:candidate_document)
    candidate = document.candidate_assignment.candidate

    result = described_class.call(
      actor: nil, candidate:, document:, request_id: 'cand-doc-access-download', disposition: 'attachment'
    )

    expect(result.url).to include('disposition=attachment')
    expect(AuditEvent.last.metadata).to include('disposition' => 'attachment')
  end

  it 'rejects documents whose attachment is missing' do
    document = create(:candidate_document)
    candidate = document.candidate_assignment.candidate
    document.file.purge

    expect do
      described_class.call(actor: nil, candidate:, document:, request_id: 'cand-doc-access-2')
    end.to raise_error(DocumentAttachmentMissingError)
  end

  it 'does not write an access audit event if URL generation fails' do
    document = create(:candidate_document)
    candidate = document.candidate_assignment.candidate

    allow(Rails.application.routes.url_helpers)
      .to receive(:rails_service_blob_proxy_path)
      .and_raise(StandardError, 'boom')

    expect do
      described_class.call(actor: nil, candidate:, document:, request_id: 'cand-doc-access-3')
    end.to raise_error(StandardError, 'boom')

    expect(AuditEvent.where(action_code: 'candidate_document_accessed')).to be_empty
  end
end
