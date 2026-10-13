# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Candidates::Imports::ExpiredPreflightCleanupService do
  it 'clears expired payloads without removing finalized row results or audit evidence' do
    batch = create(:candidate_import_batch, status: 'completed', expires_at: 1.minute.ago)
    row_result = create(:candidate_import_row_result, candidate_import_batch: batch, status: 'committed')
    audit_event = AuditEvent.create!(
      actor: batch.actor, entity_type: 'CandidateImportBatch', entity_id: batch.id,
      action_code: 'candidate_import_committed', request_id: 'cleanup-import', occurred_at: Time.current,
      metadata: { import_public_id: batch.public_id }
    )

    described_class.call

    expect(batch.reload).to have_attributes(status: 'completed', preflight_payload: nil)
    expect(row_result.reload).to be_present
    expect(audit_event.reload).to be_present
  end

  it 'invalidates an expired preview that was never confirmed' do
    batch = create(:candidate_import_batch, :awaiting_confirmation, expires_at: 1.minute.ago)

    described_class.call

    expect(batch.reload).to have_attributes(status: 'invalidated', preflight_payload: nil)
  end

  it 'leaves a confirmed import that is still waiting for its job untouched' do
    batch = create(:candidate_import_batch, status: 'queued', expires_at: 1.minute.ago)

    described_class.call

    expect(batch.reload).to have_attributes(status: 'queued')
    expect(batch.preflight_payload).to be_present
  end
end
