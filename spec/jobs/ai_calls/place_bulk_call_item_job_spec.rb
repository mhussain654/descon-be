# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::PlaceBulkCallItemJob, type: :job do
  it 'places the call for the item through the service' do
    item = create(:bulk_call_batch_item)
    service = instance_double(AiCalls::PlaceBulkCallItemService, call: nil)
    allow(AiCalls::PlaceBulkCallItemService).to receive(:new).and_return(service)

    described_class.perform_now(item.id)

    expect(AiCalls::PlaceBulkCallItemService).to have_received(:new).with(item_id: item.id, request_id: kind_of(String))
    expect(service).to have_received(:call)
  end

  it 'drops a job whose item no longer exists' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it 'marks a still-queued item failed on an unexpected error, so the candidate is not stuck, and re-raises' do
    item = create(:bulk_call_batch_item)
    allow(AiCalls::PlaceBulkCallItemService).to receive(:new).and_raise(StandardError, 'boom')

    expect { described_class.perform_now(item.id) }.to raise_error(StandardError, 'boom')

    expect(item.reload).to have_attributes(status: 'failed', skip_reason: 'provider_error')
  end
end
