# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::TriggerOutboundCallService do
  let(:configuration) do
    instance_double(
      AiCalls::Configuration,
      outbound_enabled?: true,
      robocall?: false,
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
  let(:plan) { AiCalls::OutboundCallPlan.for_admin_scenario('missing_documents') }

  def service(plan: self.plan)
    described_class.new(candidate:, plan:, actor:, request_id: 'req-1', configuration:)
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
    expect(call_record.candidate_ai_call_events.sole.event_source).to eq('admin_trigger')
  end

  it 'calls in English when the candidate has not chosen a language yet' do
    candidate.update!(preferred_locale: nil)
    stub_successful_call

    call_record = service.call

    expect(call_record.language_code).to eq('en')
    expect(call_record.communication.locale).to eq('en')
  end

  it "syncs the call's Communication status_code and provider_reference once queued" do
    stub_successful_call

    call_record = service.call

    communication = call_record.communication.reload
    expect(communication.status_code).to eq('queued')
    expect(communication.provider_reference).to eq('conversation-1')
  end

  # Regression: a 2xx ElevenLabs response missing conversation_id would
  # otherwise mark the call 'queued' with nothing to ever reconcile it by --
  # neither Twilio nor ElevenLabs cross-checks work without an id, so it
  # would stay 'queued' forever, past every reconciliation threshold.
  it 'rolls back and raises when the provider response is missing a conversation_id, creating no rows' do
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return({ callSid: 'CA-1' }.to_json)
    allow(Net::HTTP).to receive(:start).and_return(response)

    expect { service.call }.to raise_error(AiCallProviderRequestError)
    expect(CandidateAiCall.count).to eq(0)
    expect(Communication.count).to eq(0)
  end

  it 'records event_source as workflow_stage_trigger and no triggered_by when actor is nil' do
    stub_successful_call
    stage_plan = AiCalls::OutboundCallPlan.for_workflow_stage(
      build_stubbed(:workflow_stage_call_script, workflow_stage_code: 'verified')
    )

    call_record = described_class.new(candidate:, plan: stage_plan, request_id: 'req-1', configuration:).call

    expect(call_record.triggered_by).to be_nil
    expect(call_record.workflow_stage_code).to eq('verified')
    expect(call_record.candidate_ai_call_events.sole.event_source).to eq('workflow_stage_trigger')
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
      described_class.new(candidate: unassigned, plan:, actor:, request_id: 'req-1', configuration:).call
    end.to raise_error(NoCurrentAssignmentError)
  end

  it 'raises for an inactive candidate' do
    candidate.update!(active: false)

    expect { service.call }.to raise_error(InactiveAccountError)
  end

  it 'raises when constructing a plan for an unknown call_reason' do
    expect { AiCalls::OutboundCallPlan.for_admin_scenario('bogus') }.to raise_error(ArgumentError)
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

  describe 'when RoboCall is the voice provider' do
    def robocall_adapter = @robocall_adapter ||= instance_double(AiCalls::Providers::RobocallAdapter)

    def robocall_plan
      script = build_stubbed(:workflow_stage_call_script, workflow_stage_code: 'verified', voice_id: '102')
      AiCalls::OutboundCallPlan.for_workflow_stage(script)
    end

    before do
      allow(configuration).to receive(:robocall?).and_return(true)
      allow(AiCalls::Providers::RobocallAdapter).to receive(:new).and_return(robocall_adapter)
    end

    def robocall_service(plan: robocall_plan)
      described_class.new(candidate:, plan:, request_id: 'req-1', configuration:)
    end

    def result(call_id) = AiCalls::Providers::RobocallAdapter::CallResult.new(call_id:)

    it 'plays the stage voice to the candidate and queues the call, sending nothing else' do
      allow(robocall_adapter).to receive(:initiate_call).and_return(result('20076'))

      call_record = robocall_service.call

      expect(robocall_adapter).to have_received(:initiate_call)
        .with(voice_id: '102', to_number: candidate.mobile_number)
      expect(call_record).to have_attributes(
        provider_code: 'robocall', provider_voice_id: '102', robocall_call_id: '20076', status: 'queued',
        elevenlabs_agent_id: nil, elevenlabs_conversation_id: nil, agent_config_digest: nil,
        workflow_stage_code: 'verified', started_at: be_present
      )
      expect(call_record.communication).to have_attributes(status_code: 'queued', provider_reference: '20076')
      expect(call_record.candidate_ai_call_events.sole).to have_attributes(
        provider_code: 'robocall', event_source: 'workflow_stage_trigger',
        payload: include('robocall_call_id' => '20076')
      )
    end

    it 'refuses a call that has no voice, before creating anything' do
      allow(robocall_adapter).to receive(:initiate_call)

      expect { robocall_service(plan: plan).call }.to raise_error(AiCallVoiceNotConfiguredError)
      expect(robocall_adapter).not_to have_received(:initiate_call)
      expect(CandidateAiCall.count).to eq(0)
    end

    it 'keeps the call, for manual review, when RoboCall accepts it but returns no call id (never rolled back)' do
      allow(robocall_adapter).to receive(:initiate_call).and_return(result(nil))

      call_record = robocall_service.call

      expect(call_record).to have_attributes(
        status: 'completed', outcome: nil, outcome_reason: 'needs_manual_review', robocall_call_id: nil,
        failure_message: include('no call id')
      )
      expect(call_record.communication.reload.status_code).to eq('completed')
      expect(CandidateAiCall.count).to eq(1)
    end

    it 'rolls back when the RoboCall request fails' do
      allow(robocall_adapter).to receive(:initiate_call).and_raise(AiCallProviderRequestError)

      expect { robocall_service.call }.to raise_error(AiCallProviderRequestError)
      expect(CandidateAiCall.count).to eq(0)
    end
  end
end
