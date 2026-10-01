# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Tools::CreateCallbackRequest do
  let(:call_record) { create(:candidate_ai_call, :inbound) }

  it 'records the callback request time and echoes the reason' do
    result = described_class.call(candidate_ai_call: call_record, params: { 'reason' => 'call me back later' })

    expect(call_record.reload.callback_requested_at).to be_present
    expect(result).to eq(callback_requested: true, reason: 'call me back later')
  end

  it 'omits a blank reason' do
    result = described_class.call(candidate_ai_call: call_record, params: {})

    expect(result).to eq(callback_requested: true)
  end
end
