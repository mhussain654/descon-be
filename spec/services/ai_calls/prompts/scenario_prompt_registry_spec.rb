# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCalls::Prompts::ScenarioPromptRegistry do
  it 'resolves each of the 4 admin-triggered call reasons to its prompt class' do
    expect(described_class.fetch('missing_documents')).to eq(AiCalls::Prompts::MissingDocumentsPrompt)
    expect(described_class.fetch('protection_appearance_reminder'))
      .to eq(AiCalls::Prompts::ProtectionAppearanceReminderPrompt)
    expect(described_class.fetch('urgent_compliance_action')).to eq(AiCalls::Prompts::UrgentComplianceActionPrompt)
    expect(described_class.fetch('flight_information')).to eq(AiCalls::Prompts::FlightInformationPrompt)
  end

  it 'raises for an unknown call reason' do
    expect { described_class.fetch('general_helpline') }.to raise_error(ArgumentError, /Unknown outbound/)
  end
end
