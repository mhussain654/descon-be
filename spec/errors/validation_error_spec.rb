# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ValidationError do
  it 'uses the translated validation response and keeps the failing field' do
    error = described_class.new(field: :email)

    expect(error.code).to eq('validation_failed')
    expect(error.status).to eq(:unprocessable_entity)
    expect(error.field).to eq(:email)
    expect(error.message).to eq(I18n.t('api.errors.validation_failed'))
  end
end
