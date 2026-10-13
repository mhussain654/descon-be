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

  it 'still runs a confirmed import whose job starts after the preview expiry (e.g. a delayed worker)' do
    batch = create(:candidate_import_batch, actor:, expires_at: 1.minute.ago)

    described_class.call(import_id: batch.public_id, request_id: 'execute-import-late')

    expect(batch.reload).to have_attributes(status: 'completed')
    expect(batch.processed_at).to be_present
  end

  it 'never runs an unconfirmed preview' do
    batch = create(:candidate_import_batch, :awaiting_confirmation, actor:)

    described_class.call(import_id: batch.public_id, request_id: 'execute-import-preview')

    expect(batch.reload).to have_attributes(status: 'awaiting_confirmation', processed_at: nil)
  end

  it "stores a rejected row's offending cell (masked for identity numbers) for the detail page" do
    ensure_candidate_import_reference_data!
    row = {
      'full_name' => 'Late Reject', 'cnic' => '42101-1234567-1', 'mobile_number' => '+923001234567',
      'reference_number' => 'DES-007001', 'preferred_locale' => '', 'candidate_status' => '',
      'workflow_stage_code' => '', 'country_code' => 'qatar', 'project_code' => 'qatar_infrastructure',
      'craft_code' => 'Crane Opereator', 'active' => 'true', 'row_number' => 2, 'template_version' => 'v1'
    }
    batch = create(:candidate_import_batch, actor:, preflight_payload: { rows: [row] }.to_json)
    row_result = create(:candidate_import_row_result, candidate_import_batch: batch, row_number: 2)

    described_class.call(import_id: batch.public_id, request_id: 'execute-import-value')

    expect(row_result.reload).to have_attributes(status: 'rejected', error_field: 'craft_code',
                                                 error_code: 'unknown_craft_code', error_value: 'Crane Opereator')
  end

  it 'records a failed worker execution only while the batch is processing' do
    batch = create(:candidate_import_batch, actor:, status: 'processing')

    described_class.record_failure(import_id: batch.public_id, request_id: 'execute-import-failed')

    expect(batch.reload).to have_attributes(status: 'failed', error_code: 'processing_failed')
    expect(AuditEvent.where(action_code: 'candidate_import_failed', entity_id: batch.id)).to exist
  end
end
