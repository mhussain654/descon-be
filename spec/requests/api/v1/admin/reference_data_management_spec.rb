# frozen_string_literal: true

require 'rails_helper'

# Developer-only lookup management beyond create/update/retire: restore, delete
# an unused entry, refuse to delete one in use, and the full list with retired
# entries. Transactional (unlike reference_data_spec.rb), so nothing it creates
# outlives an example.
RSpec.describe 'API V1 Admin Reference Data management', type: :request do
  before { ensure_staff_authorization_reference_data! }

  def access_token_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  it 'restores a retired craft' do
    create(:craft, code: 'retired_craft', active: false)

    post '/api/v1/admin/crafts/retired_craft/restoration',
         headers: { 'Authorization' => "Bearer #{access_token_for(create(:user, role: 'developer'))}" }

    expect(response).to have_http_status(:ok)
    expect(Craft.find_by!(code: 'retired_craft')).to be_active
  end

  it 'deletes a project nothing uses' do
    create(:project, code: 'typo_project')

    delete '/api/v1/admin/projects/typo_project',
           headers: { 'Authorization' => "Bearer #{access_token_for(create(:user, role: 'developer'))}" }

    expect(response).to have_http_status(:ok)
    expect(Project.find_by(code: 'typo_project')).to be_nil
    expect(AuditEvent.where(action_code: 'reference_data_destroy').count).to eq(1)
  end

  it 'refuses to delete a country in use, asking to retire it instead' do
    country = create(:country, code: 'used_country')
    create(:candidate_assignment, country:)

    delete '/api/v1/admin/countries/used_country',
           headers: { 'Authorization' => "Bearer #{access_token_for(create(:user, role: 'developer'))}" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('reference_data_in_use')
    expect(Country.find_by(code: 'used_country')).to be_present
  end

  it 'lists every craft, retired ones too, with both names for a developer' do
    create(:craft, code: 'old_craft', name_en: 'Old', name_ur: 'پرانا', active: false)

    developer = create(:user, role: 'developer')
    get '/api/v1/admin/crafts', params: { include_retired: 'true' },
                                headers: { 'Authorization' => "Bearer #{access_token_for(developer)}" }

    row = response.parsed_body.fetch('data').find { |item| item['code'] == 'old_craft' }
    expect(row).to include('active' => false, 'name_en' => 'Old', 'name_ur' => 'پرانا')
  end

  it 'keeps the full list from staff who only use the lookups' do
    hr = create(:user, role: 'hr')
    get '/api/v1/admin/crafts', params: { include_retired: 'true' },
                                headers: { 'Authorization' => "Bearer #{access_token_for(hr)}" }

    expect(response).to have_http_status(:forbidden)
  end
end
