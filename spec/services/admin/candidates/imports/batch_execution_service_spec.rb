# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Candidates::Imports::BatchExecutionService do
  let(:actor) { create(:user) }

  it 'transitions a queued batch to partial while preserving durable rejected rows' do
    batch = create(:candidate_import_batch, actor:, status: 'queued')
    rejected_row = create(
      :candidate_import_row_result,
      candidate_import_batch: batch,
      status: 'rejected',
      error_field: 'cnic',
      error_code: 'invalid_cnic'
    )

    described_class.call(import_id: batch.public_id, request_id: 'execute-import-1')

    expect(batch.reload).to have_attributes(status: 'partial', rejected_rows: 1, committed_rows: 0)
    expect(rejected_row.reload).to have_attributes(status: 'rejected', error_code: 'invalid_cnic')
    expect(AuditEvent.where(action_code: 'candidate_import_committed', entity_id: batch.id)).to exist
  end

  it 'invalidates an expired queued batch without deleting its row results' do
    batch = create(:candidate_import_batch, actor:, expires_at: 1.minute.ago)
    row_result = create(:candidate_import_row_result, candidate_import_batch: batch)

    described_class.call(import_id: batch.public_id, request_id: 'execute-import-expired')

    expect(batch.reload).to have_attributes(status: 'invalidated', preflight_payload: nil)
    expect(row_result.reload).to be_present
  end

  it 'records a failed worker execution only while the batch is processing' do
    batch = create(:candidate_import_batch, actor:, status: 'processing')

    described_class.record_failure(import_id: batch.public_id, request_id: 'execute-import-failed')

    expect(batch.reload).to have_attributes(status: 'failed', error_code: 'processing_failed')
    expect(AuditEvent.where(action_code: 'candidate_import_failed', entity_id: batch.id)).to exist
  end
end
