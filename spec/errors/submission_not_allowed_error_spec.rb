# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SubmissionNotAllowedError do
  it 'uses the translated submission-not-allowed response' do
    error = described_class.new

    expect(error.code).to eq('submission_not_allowed')
    expect(error.status).to eq(:unprocessable_entity)
    expect(error.message).to eq(I18n.t('api.errors.submission_not_allowed'))
  end
end
