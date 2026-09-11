# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::TriggerWorkflowStageCallJob do
  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }

  it 'delegates to TriggerWorkflowStageCallService with the given arguments' do
    fake_service = instance_double(AiCalls::TriggerWorkflowStageCallService, call: nil)
    allow(AiCalls::TriggerWorkflowStageCallService).to receive(:new).and_return(fake_service)

    described_class.perform_now(candidate_assignment_id: assignment.id, workflow_stage_code: 'verified',
                                request_id: 'req-1')

    expect(AiCalls::TriggerWorkflowStageCallService).to have_received(:new).with(
      candidate_assignment_id: assignment.id, workflow_stage_code: 'verified', request_id: 'req-1'
    )
    expect(fake_service).to have_received(:call)
  end

  it 'is configured to retry on outside-calling-hours and daily-limit errors, not on outbound-disabled' do
    retry_classes = described_class.rescue_handlers.map(&:first).grep(String)

    expect(retry_classes).to include('AiCallOutsideCallingHoursError', 'AiCallDailyLimitReachedError')
    expect(retry_classes).not_to include('AiCallOutboundDisabledError')
  end
end
