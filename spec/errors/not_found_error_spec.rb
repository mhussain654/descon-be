# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NotFoundError do
  it 'uses the translated not found response' do
    error = described_class.new

    expect(error.code).to eq('not_found')
    expect(error.status).to eq(:not_found)
    expect(error.message).to eq(I18n.t('api.errors.not_found'))
  end
end
