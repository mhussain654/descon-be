# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Prompts::ScenarioPrompt do
  let(:candidate) { build_stubbed(:candidate, full_name: 'Ali Raza') }

  it 'requires subclasses to define call_reason' do
    expect { described_class.call_reason }.to raise_error(NotImplementedError)
  end

  describe 'a concrete subclass' do
    subject(:content) { AiCalls::Prompts::MissingDocumentsPrompt.build(candidate:, language_code: 'en') }

    it 'sets the candidate name and call reason as dynamic variables' do
      expect(content.dynamic_variables).to eq('candidate_name' => 'Ali Raza', 'call_reason' => 'missing_documents')
    end

    it 'overrides the first_message and language from the localized opening line' do
      expect(content.conversation_config_override.dig('agent', 'language')).to eq('en')
      expect(content.conversation_config_override.dig('agent', 'first_message')).to include('missing')
    end

    it 'renders the Urdu opening line for language_code ur' do
      urdu_content = AiCalls::Prompts::MissingDocumentsPrompt.build(candidate:, language_code: 'ur')

      expect(urdu_content.conversation_config_override.dig('agent', 'first_message')).to match(/[؀-ۿ]/)
    end
  end
end
