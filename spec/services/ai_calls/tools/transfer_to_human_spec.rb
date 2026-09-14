# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::TransferToHuman do
  let(:call_record) { create(:candidate_ai_call, :inbound) }

  it 'degrades to recording a callback request, since no live transfer destination exists yet' do
    result = described_class.call(candidate_ai_call: call_record, params: { 'reason' => 'needs a human' })

    expect(call_record.reload.callback_requested_at).to be_present
    expect(result).to eq(transfer_available: false, callback_requested: true, reason: 'needs a human')
  end

  it 'omits a blank reason' do
    result = described_class.call(candidate_ai_call: call_record, params: {})

    expect(result).to eq(transfer_available: false, callback_requested: true)
  end
end
