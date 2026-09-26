# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCallToolSecretInvalidError do
  it 'uses the translated tool-secret-invalid response' do
    error = described_class.new

    expect(error.code).to eq('ai_call_tool_secret_invalid')
    expect(error.status).to eq(:unauthorized)
    expect(error.message).to eq(I18n.t('api.errors.ai_call_tool_secret_invalid'))
  end
end
