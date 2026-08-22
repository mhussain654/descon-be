# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OpenAPI document', type: :request do
  it 'serves the OpenAPI document inline' do
    get '/openapi/openapi.yaml'

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/yaml')
    expect(response.headers['Content-Disposition']).to include('inline')
    expect(response.body).to include('openapi: 3.1.0')
    expect(response.body).to include('/api/v1/health/live')
    expect(response.body).to include('/api/v1/health/ready')
  end
end
