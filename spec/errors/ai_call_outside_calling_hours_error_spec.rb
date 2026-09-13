# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCallOutsideCallingHoursError do
  it 'uses the translated outside-calling-hours response' do
    error = described_class.new

    expect(error.code).to eq('ai_call_outside_calling_hours')
    expect(error.status).to eq(:unprocessable_content)
    expect(error.message).to eq(I18n.t('api.errors.ai_call_outside_calling_hours'))
  end
end
