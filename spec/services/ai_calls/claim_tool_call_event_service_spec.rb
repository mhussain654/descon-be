# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::ClaimToolCallEventService do
  let(:call_record) { create(:candidate_ai_call, :inbound) }

  def claim(params: { 'reason' => 'first' }, &handler)
    described_class.call(
      candidate_ai_call: call_record, tool_name: 'create_callback_request', params:, request_id: 'req-1', &handler
    )
  end

  it 'runs the handler and records the event on a genuinely new call' do
    outcome = claim { |record| { called_with: record.id } }

    expect(outcome.replayed).to be(false)
    expect(outcome.payload).to eq(called_with: call_record.id)
    expect(call_record.candidate_ai_call_events.count).to eq(1)
  end

  it 'does not re-run the handler on a replayed call with identical arguments' do
    calls = 0
    claim { calls += 1 }

    outcome = claim { calls += 1 }

    expect(calls).to eq(1)
    expect(outcome.replayed).to be(true)
    expect(call_record.candidate_ai_call_events.count).to eq(1)
  end

  it 'returns the first invocation payload on replay' do
    claim { { value: 'original' } }

    outcome = claim { { value: 'should not be returned' } }

    expect(outcome.payload).to eq('value' => 'original')
  end

  it 'treats different arguments as a distinct event' do
    claim(params: { 'reason' => 'first' }) { { ok: true } }
    outcome = claim(params: { 'reason' => 'second' }) { { ok: true } }

    expect(outcome.replayed).to be(false)
    expect(call_record.candidate_ai_call_events.count).to eq(2)
  end

  it 'is order-independent over the argument keys' do
    claim(params: { 'a' => '1', 'b' => '2' }) { { ok: true } }
    outcome = claim(params: { 'b' => '2', 'a' => '1' }) { { ok: true } }

    expect(outcome.replayed).to be(true)
  end

  # Regression: a read-only data tool asked twice with identical arguments
  # in the same call (e.g. "what's my status?" asked again later) must
  # fetch current data both times, not silently return the first answer's
  # now-stale payload -- unlike the 3 mutating tools, there's no side
  # effect here that idempotent replay needs to protect.
  def claim_read_tool(request_id: 'req-1', &handler)
    described_class.call(
      candidate_ai_call: call_record, tool_name: 'get_application_status', params: {}, request_id:, &handler
    )
  end

  it 're-runs a read-only tool on a second call with identical (empty) arguments' do
    calls = 0
    claim_read_tool(request_id: 'req-1') { calls += 1 }

    outcome = claim_read_tool(request_id: 'req-2') { calls += 1 }

    expect(calls).to eq(2)
    expect(outcome.replayed).to be(false)
    expect(call_record.candidate_ai_call_events.where(event_type: 'get_application_status').count).to eq(2)
  end
end
