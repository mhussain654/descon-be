# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::ReconcileStuckCallsJob do
  it 'reconciles only non-terminal calls that are due, leaving others untouched' do
    due = create(:candidate_ai_call, status: 'ringing', twilio_call_sid: 'CA-1', updated_at: 5.minutes.ago)
    not_due = create(:candidate_ai_call, status: 'ringing', twilio_call_sid: 'CA-2', updated_at: 1.second.ago)
    terminal = create(:candidate_ai_call, status: 'completed', updated_at: 1.hour.ago)

    fake_reconciler = instance_double(AiCalls::ReconcileCallService, call: nil)
    allow(AiCalls::ReconcileCallService).to receive(:new).and_return(fake_reconciler)

    described_class.perform_now

    expect(AiCalls::ReconcileCallService).to have_received(:new).once
    expect(AiCalls::ReconcileCallService).to have_received(:new).with(candidate_ai_call: due, request_id: anything)
    expect(AiCalls::ReconcileCallService).not_to have_received(:new).with(candidate_ai_call: not_due,
                                                                          request_id: anything)
    expect(AiCalls::ReconcileCallService).not_to have_received(:new).with(candidate_ai_call: terminal,
                                                                          request_id: anything)
  end

  it 'shares one request_id across every call reconciled in the same run' do
    create(:candidate_ai_call, status: 'ringing', twilio_call_sid: 'CA-1', updated_at: 5.minutes.ago)
    create(:candidate_ai_call, status: 'processing', twilio_call_sid: 'CA-2', updated_at: 10.minutes.ago)
    captured_request_ids = []
    fake_reconciler = instance_double(AiCalls::ReconcileCallService, call: nil)
    allow(AiCalls::ReconcileCallService).to receive(:new) do |**kwargs|
      captured_request_ids << kwargs.fetch(:request_id)
      fake_reconciler
    end

    described_class.perform_now

    expect(captured_request_ids.size).to eq(2)
    expect(captured_request_ids.uniq.size).to eq(1)
  end
end
