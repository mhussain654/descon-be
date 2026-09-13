# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::ConversationInitiationPayload do
  it 'reads the conversation id and caller_id-shaped caller number' do
    payload = described_class.new('data' => { 'conversation_id' => 'conversation-1', 'caller_id' => '+923001234512' })

    expect(payload.conversation_id).to eq('conversation-1')
    expect(payload.caller_number).to eq('+923001234512')
  end

  it 'falls back to a nested twilio caller/from field' do
    payload = described_class.new('data' => { 'conversation_id' => 'c1', 'twilio' => { 'caller' => '+923001234512' } })

    expect(payload.caller_number).to eq('+923001234512')
  end

  it 'handles a missing or malformed payload without raising' do
    empty = described_class.new(nil)

    expect(empty.conversation_id).to be_nil
    expect(empty.caller_number).to be_nil
  end
end
