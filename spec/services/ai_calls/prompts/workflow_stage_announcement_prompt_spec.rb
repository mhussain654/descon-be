# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Prompts::WorkflowStageAnnouncementPrompt do
  subject(:content) do
    described_class.new(announcement: 'Your documents have been verified.').build(candidate:, language_code: 'en')
  end

  let(:candidate) { build_stubbed(:candidate, full_name: 'Ali Raza') }

  it 'sets the candidate name and a fixed call_reason as dynamic variables' do
    expect(content.dynamic_variables).to eq('candidate_name' => 'Ali Raza',
                                            'call_reason' => 'workflow_stage_notification')
  end

  it 'overrides the first_message with the given announcement, and the language' do
    expect(content.conversation_config_override.dig('agent',
                                                    'first_message')).to eq('Your documents have been verified.')
    expect(content.conversation_config_override.dig('agent', 'language')).to eq('en')
  end
end
