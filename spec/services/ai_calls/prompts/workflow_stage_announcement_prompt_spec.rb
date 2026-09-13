# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Prompts::WorkflowStageAnnouncementPrompt do
  let(:candidate) { build_stubbed(:candidate, full_name: 'Ali Raza') }

  def build_prompt(announcement_en: 'Your documents have been verified.', announcement_ur: nil)
    described_class.new(announcement_en:, announcement_ur:)
  end

  it 'sets the candidate name and a fixed call_reason as dynamic variables' do
    content = build_prompt.build(candidate:, language_code: 'en')

    expect(content.dynamic_variables).to eq('candidate_name' => 'Ali Raza',
                                            'call_reason' => 'workflow_stage_notification')
  end

  it 'uses announcement_en and sets the language to en for an English-preferring candidate' do
    content = build_prompt(announcement_en: 'Your documents have been verified.').build(candidate:, language_code: 'en')

    expect(content.conversation_config_override.dig('agent',
                                                    'first_message')).to eq('Your documents have been verified.')
    expect(content.conversation_config_override.dig('agent', 'language')).to eq('en')
  end

  it 'uses announcement_ur and sets the language to ur for an Urdu-preferring candidate' do
    content = build_prompt(announcement_ur: 'آپ کی دستاویزات کی تصدیق ہو گئی ہے۔').build(candidate:,
                                                                                         language_code: 'ur')

    expect(content.conversation_config_override.dig('agent',
                                                    'first_message')).to eq('آپ کی دستاویزات کی تصدیق ہو گئی ہے۔')
    expect(content.conversation_config_override.dig('agent', 'language')).to eq('ur')
  end

  it 'falls back to announcement_en when the Urdu-preferring candidate has no Urdu wording yet' do
    content = build_prompt(announcement_en: 'Your documents have been verified.', announcement_ur: nil)
              .build(candidate:, language_code: 'ur')

    expect(content.conversation_config_override.dig('agent',
                                                    'first_message')).to eq('Your documents have been verified.')
    expect(content.conversation_config_override.dig('agent', 'language')).to eq('ur')
  end
end
