# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkCallBatchItem do
  it 'has a valid factory, queued by default' do
    expect(create(:bulk_call_batch_item)).to have_attributes(status: 'queued', skip_reason: nil)
  end

  it 'only accepts a known status and skip reason' do
    expect(build(:bulk_call_batch_item, status: 'done')).not_to be_valid
    expect(build(:bulk_call_batch_item, status: 'skipped', skip_reason: 'because')).not_to be_valid
    expect(build(:bulk_call_batch_item, status: 'skipped', skip_reason: 'stage_changed')).to be_valid
  end

  it 'allows a candidate once per batch' do
    item = create(:bulk_call_batch_item)

    duplicate = build(:bulk_call_batch_item, bulk_call_batch: item.bulk_call_batch, candidate: item.candidate,
                                             candidate_assignment: item.candidate_assignment)
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'scopes queued items' do
    queued = create(:bulk_call_batch_item)
    create(:bulk_call_batch_item, status: 'placed')

    expect(described_class.queued).to contain_exactly(queued)
  end
end
