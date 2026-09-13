# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::TriggerWorkflowStageCallService do
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

  def service(workflow_stage_code: 'verified')
    described_class.new(candidate_assignment_id: assignment.id, workflow_stage_code:, request_id: 'req-1',
                        configuration:)
  end

  def stub_successful_call
    call_count = 0
    allow(Net::HTTP).to receive(:start) do
      call_count += 1
      response = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(response).to receive(:body).and_return(
        { conversation_id: "conversation-#{call_count}", callSid: "CA-#{call_count}" }.to_json
      )
      response
    end
  end

  it 'is a no-op when the stage has no active script' do
    expect(service.call).to be_nil
    expect(CandidateAiCall.count).to eq(0)
  end

  it 'is a no-op when the stage script is inactive' do
    create(:workflow_stage_call_script, workflow_stage_code: 'verified', active: false)

    expect(service.call).to be_nil
    expect(CandidateAiCall.count).to eq(0)
  end

  it 'places the call for an active script, unattributed to any admin' do
    create(:workflow_stage_call_script, workflow_stage_code: 'verified',
                                        announcement_en: 'Your documents are verified.')
    stub_successful_call

    call_record = service.call

    expect(call_record.call_reason).to eq('workflow_stage_notification')
    expect(call_record.workflow_stage_code).to eq('verified')
    expect(call_record.triggered_by).to be_nil
    expect(call_record.status).to eq('queued')
  end

  it 'never triggers a second call for the same assignment and stage' do
    create(:workflow_stage_call_script, workflow_stage_code: 'verified')
    stub_successful_call

    service.call
    result = service.call

    expect(result).to be_nil
    expect(CandidateAiCall.count).to eq(1)
  end

  it 'allows a different stage to still trigger its own call for the same assignment' do
    create(:workflow_stage_call_script, workflow_stage_code: 'verified')
    create(:workflow_stage_call_script, workflow_stage_code: 'fee_paid')
    stub_successful_call

    service(workflow_stage_code: 'verified').call
    result = service(workflow_stage_code: 'fee_paid').call

    expect(result).to be_present
    expect(CandidateAiCall.count).to eq(2)
  end

  it 'is a no-op for an inactive candidate' do
    create(:workflow_stage_call_script, workflow_stage_code: 'verified')
    candidate.update!(active: false)

    expect(service.call).to be_nil
    expect(CandidateAiCall.count).to eq(0)
  end

  it 'propagates a guard failure (e.g. outbound disabled) to the caller' do
    create(:workflow_stage_call_script, workflow_stage_code: 'verified')
    allow(configuration).to receive(:outbound_enabled?).and_return(false)

    expect { service.call }.to raise_error(AiCallOutboundDisabledError)
  end
end
