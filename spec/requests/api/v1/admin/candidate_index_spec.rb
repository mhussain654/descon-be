# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Index', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  def token_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def indexed_candidate(attributes, references = {})
    candidate = create(:candidate, **attributes, status_code: 'documents_pending')
    create(:candidate_assignment, candidate:, **references)
    candidate
  end

  def remove_permission!(role_code, permission_code)
    role_permission = RolePermission.joins(:role, :permission).find_by!(
      roles: { code: role_code }, permissions: { code: permission_code }
    )
    role_permission.destroy!
  end

  it 'searches normalized identifiers and partial names with database filters' do
    actor = create(:user, role: 'hr')
    candidate = indexed_candidate(
      { full_name: 'Ayesha Khan', cnic: '42101-1234567-1', passport_number: 'AB123456' },
      { reference_number: 'DES-SEARCH-1' }
    )
    headers = { 'Authorization' => "Bearer #{token_for(actor)}" }

    %w[Ayesha 4210112345671 ab123456 des-search-1].each do |search|
      get '/api/v1/admin/candidates', params: { search: }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data').map { |item| item.fetch('id') }).to include(candidate.public_id)
    end
  end

  it 'filters by status and assignment references, with pagination metadata' do
    actor = create(:user, role: 'hr')
    country = create(:country, code: 'mps305_country')
    project = create(:project, code: 'mps305_project')
    craft = create(:craft, code: 'mps305_craft')
    candidate = indexed_candidate(
      { full_name: 'Filtered', cnic: '42101-1234567-2', passport_number: nil },
      { reference_number: 'DES-FILTER-1', country:, project:, craft: }
    )

    get '/api/v1/admin/candidates',
        params: { filter: {
          status: 'documents_pending', country_code: country.code, project_code: project.code, craft_code: craft.code
        }, page: { size: 1 } },
        headers: { 'Authorization' => "Bearer #{token_for(actor)}" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 0, 'id')).to eq(candidate.public_id)
    expect(response.parsed_body.dig('meta', 'pagination', 'per_page')).to eq(1)
    expect(response.parsed_body.dig('meta', 'applied_filters')).to include('country_code' => country.code)
  end

  it 'uses only the authoritative current assignment for filters, reference search, and sorting' do
    actor = create(:user, role: 'hr')
    old_country = create(:country, code: 'mps305_old_country')
    current_country = create(:country, code: 'mps305_current_country')
    candidate = indexed_candidate(
      { full_name: 'Current Assignment', cnic: '42101-1234567-3', passport_number: nil },
      { reference_number: 'DES-OLD-REF', country: old_country, created_at: 2.days.ago }
    )
    create(:candidate_assignment, candidate:, country: current_country, reference_number: 'DES-CURRENT-REF')
    headers = { 'Authorization' => "Bearer #{token_for(actor)}" }

    get '/api/v1/admin/candidates', params: { filter: { country_code: old_country.code } }, headers: headers
    expect(response.parsed_body.fetch('data')).not_to include(hash_including('id' => candidate.public_id))

    get '/api/v1/admin/candidates',
        params: { filter: { country_code: current_country.code }, sort: 'reference_number' }, headers: headers
    data = response.parsed_body.fetch('data')
    expect(data.count { |item| item.fetch('id') == candidate.public_id }).to eq(1)
    result = data.find { |item| item.fetch('id') == candidate.public_id }
    expect(result.dig('assignment', 'reference_number')).to eq('DES-CURRENT-REF')
  end

  it 'rejects invalid query inputs and unauthorized viewers' do
    actor = create(:user, role: 'finance')
    remove_permission!('finance', 'view_candidates')

    get '/api/v1/admin/candidates', headers: { 'Authorization' => "Bearer #{token_for(actor)}" }
    expect(response).to have_http_status(:forbidden)

    manager = create(:user, role: 'hr')
    get '/api/v1/admin/candidates', params: { sort: 'cnic' },
                                    headers: { 'Authorization' => "Bearer #{token_for(manager)}" }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('sort.cnic')
  end
end
