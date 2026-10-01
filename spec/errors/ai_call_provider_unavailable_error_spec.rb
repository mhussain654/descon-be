# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCallProviderUnavailableError do
  it 'uses the translated provider-unavailable response' do
    error = described_class.new

    expect(error.code).to eq('ai_call_provider_unavailable')
    expect(error.status).to eq(:service_unavailable)
    expect(error.message).to eq(I18n.t('api.errors.ai_call_provider_unavailable'))
  end
end
