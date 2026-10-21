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
                                                          announcement_en: 'Your documents have been verified.')

      plan = described_class.for_workflow_stage(script)

      expect(plan.call_reason).to eq('workflow_stage_notification')
      expect(plan.workflow_stage_code).to eq('verified')
      expect(plan.prompt_source).to be_a(AiCalls::Prompts::WorkflowStageAnnouncementPrompt)
    end
  end

  describe '.for_voice' do
    it "is an admin's single call with just a voice, and is not a bulk call" do
      plan = described_class.for_voice(voice_id: '538')

      expect(plan).to have_attributes(call_reason: 'voice_call', voice_id: '538', prompt_source: nil,
                                      workflow_stage_code: nil)
      expect(plan).not_to be_bulk
    end
  end

  describe '.for_bulk' do
    it 'is a bulk call with just a voice: no scenario text and no workflow stage' do
      plan = described_class.for_bulk(voice_id: '102')

      expect(plan).to have_attributes(call_reason: 'bulk_voice_call', voice_id: '102', prompt_source: nil,
                                      workflow_stage_code: nil)
      expect(plan).to be_bulk
    end

    it 'marks no other plan as bulk' do
      expect(described_class.for_admin_scenario('missing_documents')).not_to be_bulk
    end
  end
end
