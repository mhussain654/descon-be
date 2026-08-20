# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Health Ready', type: :request do
  it 'returns a generic service unavailable error when the check fails' do
    allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::StatementInvalid.new('boom'))

    get '/api/v1/health/ready'

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.dig('errors', 0, 'message')).to eq('Service is temporarily unavailable.')
  end
end
