# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCallOutboundDisabledError do
  it 'uses the translated outbound-disabled response' do
    error = described_class.new

    expect(error.code).to eq('ai_call_outbound_disabled')
    expect(error.status).to eq(:service_unavailable)
    expect(error.message).to eq(I18n.t('api.errors.ai_call_outbound_disabled'))
  end
end
