# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCallDailyLimitReachedError do
  it 'uses the translated daily-limit response' do
    error = described_class.new

    expect(error.code).to eq('ai_call_daily_limit_reached')
    expect(error.status).to eq(:too_many_requests)
    expect(error.message).to eq(I18n.t('api.errors.ai_call_daily_limit_reached'))
  end
end
