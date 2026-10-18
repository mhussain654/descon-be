# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::PollRobocallCallsJob, type: :job do
  it 'polls every open RoboCall call and nothing else' do
    open_call = create(:candidate_ai_call, provider_code: 'robocall', robocall_call_id: '1', status: 'queued')
    create(:candidate_ai_call, provider_code: 'robocall', robocall_call_id: '2', status: 'completed')
    create(:candidate_ai_call, provider_code: 'elevenlabs', status: 'queued')
    service = instance_double(AiCalls::PollRobocallCallService, call: nil)
    allow(AiCalls::PollRobocallCallService).to receive(:new).and_return(service)

    described_class.perform_now

    expect(AiCalls::PollRobocallCallService).to have_received(:new)
      .with(candidate_ai_call: open_call, request_id: kind_of(String)).once
  end
end
