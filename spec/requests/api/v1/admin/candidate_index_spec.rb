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
      { registration_number: 300_001 }
    )
    headers = { 'Authorization' => "Bearer #{token_for(actor)}" }

    %w[Ayesha 4210112345671 ab123456 300001].each do |search|
      get '/api/v1/admin/candidates', params: { search: }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data').map { |item| item.fetch('id') }).to include(candidate.public_id)
    end
  end

  it 'searches by mobile number in any spelling, or part of one' do
    actor = create(:user, role: 'hr')
    candidate = indexed_candidate(
      { full_name: 'Mobile Match', cnic: '42101-7654321-1', mobile_number: '+923001234567' },
      { registration_number: 300_002 }
    )
    other = indexed_candidate({ full_name: 'Someone Else', cnic: '42101-7654321-2', mobile_number: '+923331112223' },
                              { registration_number: 300_003 })
    headers = { 'Authorization' => "Bearer #{token_for(actor)}" }

    ['03001234567', '923001234567', '+92 300 1234567', '0300-1234567', '1234567'].each do |search|
      get '/api/v1/admin/candidates', params: { search: }, headers: headers
      ids = response.parsed_body.fetch('data').map { |item| item.fetch('id') }
      expect(ids).to eq([candidate.public_id]), search
    end
    expect(other).to be_persisted
  end

  it 'does not treat a short number or a name with digits as a mobile number' do
    actor = create(:user, role: 'hr')
    indexed_candidate({ full_name: 'Mobile Match', cnic: '42101-7654321-3', mobile_number: '+923001234567' },
                      { registration_number: 300_004 })
    headers = { 'Authorization' => "Bearer #{token_for(actor)}" }

    %w[123456 Ali1234567].each do |search|
      get '/api/v1/admin/candidates', params: { search: }, headers: headers
      expect(response.parsed_body.fetch('data')).to be_empty, search
    end
  end

  it 'filters by status and assignment references, with pagination metadata' do
    actor = create(:user, role: 'hr')
    country = create(:country, code: 'mps305_country')
    project = create(:project, code: 'mps305_project')
    craft = create(:craft, code: 'mps305_craft')
    candidate = indexed_candidate(
      { full_name: 'Filtered', cnic: '42101-1234567-2', passport_number: nil },
      { country:, project:, craft: }
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

  it 'filters by one file (registration) number or a range of them' do
    headers = { 'Authorization' => "Bearer #{token_for(create(:user, role: 'hr'))}" }
    numbers = [710_001, 710_002, 710_003, 710_010]
    candidates = numbers.map.with_index do |number, index|
      indexed_candidate({ full_name: "File #{number}", cnic: "42101-765432#{index}-1" },
                        { registration_number: number })
    end
    ids = lambda do |value|
      get '/api/v1/admin/candidates', params: { filter: { registration_number: value } }, headers: headers
      response.parsed_body.fetch('data').map { |item| item.fetch('id') }
    end

    expect(ids.call('710002')).to eq([candidates[1].public_id])
    expect(ids.call(' 710003 - 710001 ')).to match_array(candidates.first(3).map(&:public_id))
    expect(response.parsed_body.dig('meta', 'applied_filters')).to include('registration_number' => ' 710003 - 710001 ')

    get '/api/v1/admin/candidates', params: { filter: { registration_number: '7100a' } }, headers: headers
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.registration_number')
  end

  it 'filters by SMS sender' do
    headers = { 'Authorization' => "Bearer #{token_for(create(:user, role: 'hr'))}" }
    masking = indexed_candidate({ full_name: 'Brand Name', cnic: '42101-8765432-1' })
    short_code = indexed_candidate({ full_name: 'Short Code', cnic: '42101-8765432-2', sms_sender: 'short_code' })
    ids = lambda do |value|
      get '/api/v1/admin/candidates', params: { filter: { sms_sender: value } }, headers: headers
      response.parsed_body.fetch('data').map { |item| item.fetch('id') }
    end

    expect(ids.call('short_code')).to eq([short_code.public_id])
    expect(ids.call('masking')).to eq([masking.public_id])
    expect(response.parsed_body.dig('meta', 'applied_filters')).to include('sms_sender' => 'masking')

    get '/api/v1/admin/candidates', params: { filter: { sms_sender: 'whatsapp' } }, headers: headers
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('filter.sms_sender')
  end

  it 'uses only the authoritative current assignment for filters, reference search, and sorting' do
    actor = create(:user, role: 'hr')
    old_country = create(:country, code: 'mps305_old_country')
    current_country = create(:country, code: 'mps305_current_country')
    candidate = indexed_candidate(
      { full_name: 'Current Assignment', cnic: '42101-1234567-3', passport_number: nil },
      { registration_number: 300_002, country: old_country, created_at: 2.days.ago }
    )
    create(:candidate_assignment, candidate:, country: current_country, registration_number: 300_003)
    headers = { 'Authorization' => "Bearer #{token_for(actor)}" }

    get '/api/v1/admin/candidates', params: { filter: { country_code: old_country.code } }, headers: headers
    expect(response.parsed_body.fetch('data')).not_to include(hash_including('id' => candidate.public_id))

    get '/api/v1/admin/candidates',
        params: { filter: { country_code: current_country.code }, sort: 'registration_number' }, headers: headers
    data = response.parsed_body.fetch('data')
    expect(data.count { |item| item.fetch('id') == candidate.public_id }).to eq(1)
    result = data.find { |item| item.fetch('id') == candidate.public_id }
    expect(result.dig('assignment', 'registration_number')).to eq(300_003)
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
