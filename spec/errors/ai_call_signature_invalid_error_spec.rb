# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCallSignatureInvalidError do
  it 'uses the translated signature-invalid response with a default field' do
    error = described_class.new

    expect(error.code).to eq('ai_call_signature_invalid')
    expect(error.status).to eq(:unauthorized)
    expect(error.field).to eq('ai_call_webhook.signature')
    expect(error.message).to eq(I18n.t('api.errors.ai_call_signature_invalid'))
  end

  it 'accepts an explicit field override' do
    error = described_class.new(field: 'ai_call_tool.signature')

    expect(error.field).to eq('ai_call_tool.signature')
  end
end
