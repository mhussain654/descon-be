# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe 'API V1 Admin Candidate Import Template', type: :request do
  before { ensure_staff_authorization_reference_data! }

  def token_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  it 'downloads the versioned UTF-8 template with parser-compatible headers and synthetic data' do
    actor = create(:user, role: 'hr')

    get '/api/v1/admin/candidate_imports/template', headers: { 'Authorization' => "Bearer #{token_for(actor)}" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/csv')
    expect(response.headers['Content-Disposition']).to include('candidate-import-template-v1.csv')
    rows = CSV.parse(response.body, headers: true)
    expect(rows.headers).to eq(Admin::Candidates::Imports::Template.headers)
    expect(rows.first.fetch('cnic')).to eq('42101-1234567-1')
    expect(rows.first.fetch('next_of_kin_name')).to eq('مثالی سرپرست')
  end

  it 'requires candidate-management permission' do
    actor = create(:user, role: 'finance')

    get '/api/v1/admin/candidate_imports/template', headers: { 'Authorization' => "Bearer #{token_for(actor)}" }

    expect(response).to have_http_status(:forbidden)
  end
end
