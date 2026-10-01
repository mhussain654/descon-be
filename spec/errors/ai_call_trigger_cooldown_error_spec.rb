# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCallTriggerCooldownError do
  it 'uses the translated cooldown response' do
    error = described_class.new

    expect(error.code).to eq('ai_call_trigger_cooldown')
    expect(error.status).to eq(:too_many_requests)
    expect(error.message).to eq(I18n.t('api.errors.ai_call_trigger_cooldown'))
  end
end
