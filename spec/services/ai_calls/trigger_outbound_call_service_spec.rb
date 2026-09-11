# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::TriggerOutboundCallService do
  let(:configuration) do
    instance_double(
      AiCalls::Configuration,
      outbound_enabled?: true,
      calling_hours_start: 0,
      calling_hours_end: 24,
      admin_trigger_rate_limit_per_hour: 50,
      daily_outbound_call_limit: 200,
      outbound_trigger_cooldown_minutes: 60,
      elevenlabs_api_key: 'elevenlabs-key',
      elevenlabs_base_url: 'https://api.elevenlabs.io',
      elevenlabs_outbound_agent_id: 'agent-out-1',
      elevenlabs_agent_phone_number_id: 'phone-1',
      elevenlabs_open_timeout: 5,
      elevenlabs_read_timeout: 15,
      recording_enabled?: false
    )
  end

  let(:candidate) { create(:candidate) }
  let!(:assignment) { create(:candidate_assignment, candidate:) }
  let(:actor) { create(:user, role: 'admin') }

  def service
    described_class.new(candidate:, call_reason: 'missing_documents', actor:, request_id: 'req-1', configuration:)
  end

  def stub_successful_call
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return({ conversation_id: 'conversation-1', callSid: 'CA-1' }.to_json)
    allow(Net::HTTP).to receive(:start).and_return(response)
  end

  it 'creates the Communication/CandidateAiCall/CandidateAiCallEvent rows and queues the call' do
    stub_successful_call

    call_record = service.call

    expect(call_record).to be_a(CandidateAiCall)
    expect(call_record.status).to eq('queued')
    expect(call_record.elevenlabs_conversation_id).to eq('conversation-1')
    expect(call_record.twilio_call_sid).to eq('CA-1')
    expect(call_record.communication.channel_code).to eq('ai_voice_call')
    expect(call_record.communication.recipient_masked).to be_present
    expect(call_record.candidate_ai_call_events.sole.event_type).to eq('call_initiated')
  end

  it 'raises when outbound calling is disabled and creates no rows' do
    allow(configuration).to receive(:outbound_enabled?).and_return(false)

    expect { service.call }.to raise_error(AiCallOutboundDisabledError)
    expect(CandidateAiCall.count).to eq(0)
  end

  it 'raises when the candidate has no current assignment' do
    assignment.destroy!
    unassigned = create(:candidate)

    expect do
      described_class.new(candidate: unassigned, call_reason: 'missing_documents', actor:, request_id: 'req-1',
                          configuration:).call
    end.to raise_error(NoCurrentAssignmentError)
  end

  it 'raises for an inactive candidate' do
    candidate.update!(active: false)

    expect { service.call }.to raise_error(InactiveAccountError)
  end

  it 'raises for an unknown call_reason before creating any rows' do
    expect do
      described_class.new(candidate:, call_reason: 'bogus', actor:, request_id: 'req-1', configuration:).call
    end.to raise_error(ArgumentError)
    expect(CandidateAiCall.count).to eq(0)
  end

  it 'rolls back and creates no rows when the provider call fails' do
    response = Net::HTTPBadRequest.new('1.1', '400', 'Bad Request')
    allow(response).to receive(:body).and_return({ error: 'invalid' }.to_json)
    allow(Net::HTTP).to receive(:start).and_return(response)

    expect { service.call }.to raise_error(AiCallProviderRequestError)
    expect(CandidateAiCall.count).to eq(0)
    expect(Communication.count).to eq(0)
  end

  it 'enforces the outbound-call guard checks (cooldown)' do
    stub_successful_call
    service.call

    expect { service.call }.to raise_error(AiCallTriggerCooldownError)
  end
end
