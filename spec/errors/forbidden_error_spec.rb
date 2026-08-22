# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ForbiddenError do
  it 'uses the translated forbidden response' do
    error = described_class.new

    expect(error.code).to eq('forbidden')
    expect(error.status).to eq(:forbidden)
    expect(error.message).to eq(I18n.t('api.errors.forbidden'))
  end
end
