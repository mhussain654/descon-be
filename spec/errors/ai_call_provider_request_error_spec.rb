# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCallProviderRequestError do
  it 'uses the translated provider-request-failed response' do
    error = described_class.new

    expect(error.code).to eq('ai_call_provider_request_failed')
    expect(error.status).to eq(:bad_gateway)
    expect(error.message).to eq(I18n.t('api.errors.ai_call_provider_request_failed'))
  end
end
