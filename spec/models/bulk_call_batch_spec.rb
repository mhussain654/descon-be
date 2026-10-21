# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkCallBatch do
  it 'has a valid factory and assigns a public id' do
    expect(create(:bulk_call_batch).public_id).to be_present
  end

  it 'only accepts a canonical workflow stage and positive counts' do
    expect(build(:bulk_call_batch, workflow_stage_code: 'nonsense')).not_to be_valid
    expect(build(:bulk_call_batch, requested_limit: 0)).not_to be_valid
    expect(build(:bulk_call_batch, selected_count: 0)).not_to be_valid
  end

  it 'counts its items by status, zero-filled' do
    batch = create(:bulk_call_batch)
    create(:bulk_call_batch_item, bulk_call_batch: batch, status: 'placed')
    create(:bulk_call_batch_item, bulk_call_batch: batch, status: 'placed')
    create(:bulk_call_batch_item, bulk_call_batch: batch, status: 'skipped', skip_reason: 'stage_changed')

    expect(batch.status_counts).to eq('queued' => 0, 'placed' => 2, 'skipped' => 1, 'failed' => 0)
  end
end
