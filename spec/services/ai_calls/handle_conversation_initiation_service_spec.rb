# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::HandleConversationInitiationService do
  let(:configuration) do
    instance_double(AiCalls::Configuration, elevenlabs_webhook_signing_secret: 'webhook-secret',
                                            elevenlabs_inbound_agent_id: 'agent-in-1')
  end

  def signed_header(body:, timestamp: Time.current.to_i, secret: 'webhook-secret')
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{body}")
    "t=#{timestamp},v0=#{signature}"
  end

  def service(params:)
    described_class.new(header: signed_header(body: params.to_json), raw_body: params.to_json,
                        params:, request_id: 'req-1', configuration:)
  end

  it 'creates a Communication/CandidateAiCall row for an unmatched caller, uniformly' do
    call_record = service(params: { data: { conversation_id: 'conversation-1', caller_id: '+920000000000' } }).call

    expect(call_record.direction).to eq('inbound')
    expect(call_record.call_reason).to eq('general_helpline')
    expect(call_record.candidate).to be_nil
    expect(call_record.verification_status).to eq('pending')
    expect(call_record.status).to eq('in_progress')
    expect(call_record.communication.channel_code).to eq('ai_voice_call')
    expect(call_record.communication.candidate_assignment_id).to be_nil
  end

  it 'links the candidate when the caller number matches one' do
    candidate = create(:candidate)
    create(:candidate_assignment, candidate:)

    call_record = service(
      params: { data: { conversation_id: 'conversation-2', caller_id: candidate.mobile_number } }
    ).call

    expect(call_record.candidate).to eq(candidate)
    expect(call_record.candidate_assignment).to eq(candidate.current_assignment)
  end

  it 'never persists the raw caller number outside the dedicated column' do
    candidate = create(:candidate)
    call_record = service(
      params: { data: { conversation_id: 'conversation-3', caller_id: candidate.mobile_number } }
    ).call

    expect(call_record.caller_number).to eq(candidate.mobile_number)
    expect(call_record.caller_number_masked).not_to eq(candidate.mobile_number)
    expect(call_record.communication.recipient_masked).not_to eq(candidate.mobile_number)
  end

  it 'is idempotent -- a redelivered webhook for the same conversation_id returns the existing row' do
    params = { data: { conversation_id: 'conversation-4', caller_id: '+920000000000' } }

    first = service(params:).call
    second = service(params:).call

    expect(second.id).to eq(first.id)
    expect(CandidateAiCall.where(elevenlabs_conversation_id: 'conversation-4').count).to eq(1)
  end

  it 'raises when the signature is invalid' do
    body = { data: { conversation_id: 'conversation-5' } }.to_json

    expect do
      described_class.new(header: "t=1,v0=#{'0' * 64}", raw_body: body,
                          params: { data: { conversation_id: 'conversation-5' } }, request_id: 'req-1',
                          configuration:).call
    end.to raise_error(AiCallSignatureInvalidError)
  end

  it 'raises when no conversation_id is present' do
    expect { service(params: { data: {} }).call }.to raise_error(AiCallProviderRequestError)
  end
end
