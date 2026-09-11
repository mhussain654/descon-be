# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::OutboundCallPlan do
  describe '.for_admin_scenario' do
    it 'resolves the matching ScenarioPrompt class and carries no workflow_stage_code' do
      plan = described_class.for_admin_scenario('missing_documents')

      expect(plan.call_reason).to eq('missing_documents')
      expect(plan.prompt_source).to eq(AiCalls::Prompts::MissingDocumentsPrompt)
      expect(plan.workflow_stage_code).to be_nil
    end
  end

  describe '.for_workflow_stage' do
    it 'sets call_reason to workflow_stage_notification and wraps the script announcement' do
      script = build_stubbed(:workflow_stage_call_script, workflow_stage_code: 'verified',
                                                          announcement: 'Your documents have been verified.')

      plan = described_class.for_workflow_stage(script)

      expect(plan.call_reason).to eq('workflow_stage_notification')
      expect(plan.workflow_stage_code).to eq('verified')
      expect(plan.prompt_source).to be_a(AiCalls::Prompts::WorkflowStageAnnouncementPrompt)
    end
  end
end
