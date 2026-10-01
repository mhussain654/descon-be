# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCallAdminRateLimitedError do
  it 'uses the translated admin-rate-limited response' do
    error = described_class.new

    expect(error.code).to eq('ai_call_admin_rate_limited')
    expect(error.status).to eq(:too_many_requests)
    expect(error.message).to eq(I18n.t('api.errors.ai_call_admin_rate_limited'))
  end
end
