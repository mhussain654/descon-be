# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Candidate Campaigns', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_canonical_workflow_stages!
  end

  def auth_headers(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  describe 'GET /api/v1/admin/campaigns' do
    it 'lists active campaigns, the Test campaign first, with candidate counts, for any staff member' do
      test_campaign = create(:campaign, :test)
      campaign = create(:campaign)
      create(:campaign, active: false)
      create_list(:candidate_assignment, 2, campaign:)

      get '/api/v1/admin/campaigns', headers: auth_headers(create(:user, role: 'finance'))

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body.fetch('data')
      expect(rows.pluck('id')).to eq([test_campaign.public_id, campaign.public_id])
      expect(rows.last).to include('code' => campaign.code, 'kind' => 'regular', 'candidate_count' => 2,
                                   'country' => { 'code' => campaign.country.code, 'name' => campaign.country.name_en })
    end

    it 'includes retired campaigns when asked' do
      retired = create(:campaign, active: false)

      get '/api/v1/admin/campaigns', params: { include_retired: 'true' },
                                     headers: auth_headers(create(:user, role: 'hr'))

      expect(response.parsed_body.fetch('data').pluck('id')).to include(retired.public_id)
    end

    it 'rejects an unauthenticated request' do
      get '/api/v1/admin/campaigns'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/admin/campaigns' do
    it 'creates a campaign coded by date and country, named by default' do
      country = create(:country, code: 'oman_campaign', name_en: 'Oman')

      post '/api/v1/admin/campaigns',
           params: { campaign: { country_code: 'oman_campaign', start_date: '2026-11-26' } },
           headers: auth_headers(create(:user, role: 'hr'))

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.fetch('data'))
        .to include('code' => '2026-11-26-OMAN_CAMPAIGN', 'name' => '2026-11-26 Oman', 'kind' => 'regular',
                    'candidate_count' => 0)
      expect(Campaign.find_by!(code: '2026-11-26-OMAN_CAMPAIGN').country).to eq(country)
    end

    it 'uses the name staff give, and today by default' do
      create(:country, code: 'uae_campaign')

      post '/api/v1/admin/campaigns',
           params: { campaign: { country_code: 'uae_campaign', name: 'Electricians' } },
           headers: auth_headers(create(:user, role: 'hr'))

      expect(response.parsed_body.fetch('data')).to include('name' => 'Electricians',
                                                            'code' => "#{Date.current.iso8601}-UAE_CAMPAIGN")
    end

    it 'refuses an unknown country or a malformed date' do
      headers = auth_headers(create(:user, role: 'hr'))
      create(:country, code: 'kuwait_campaign')

      post '/api/v1/admin/campaigns', params: { campaign: { country_code: 'nowhere' } }, headers: headers
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('campaign.country_code')

      post '/api/v1/admin/campaigns',
           params: { campaign: { country_code: 'kuwait_campaign', start_date: 'soon' } }, headers: headers
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('campaign.start_date')
    end

    it 'forbids staff who cannot manage candidates' do
      post '/api/v1/admin/campaigns', params: { campaign: { country_code: 'qatar' } },
                                      headers: auth_headers(create(:user, role: 'finance'))

      expect(response).to have_http_status(:forbidden)
    end
  end

  # The working campaign narrows candidate lists, dashboards and reports.
  describe 'working campaign filter' do
    let(:campaign) { create(:campaign) }
    let!(:in_campaign) { create(:candidate_assignment, campaign:).candidate }
    let!(:test_candidate) { create(:candidate_assignment, campaign: create(:campaign, :test)).candidate }
    let!(:other) { create(:candidate_assignment).candidate }

    def user_with_campaign(role, selected_campaign) = create(:user, role:, selected_campaign:)

    it 'narrows the candidate list to the working campaign' do
      get '/api/v1/admin/candidates', headers: auth_headers(user_with_campaign('hr', campaign))

      expect(response.parsed_body.fetch('data').pluck('id')).to eq([in_campaign.public_id])
      expect(response.parsed_body.dig('data', 0, 'assignment', 'campaign')).to include('code' => campaign.code)
    end

    it 'leaves the Test campaign out of all campaigns' do
      get '/api/v1/admin/candidates', headers: auth_headers(user_with_campaign('hr', nil))

      ids = response.parsed_body.fetch('data').pluck('id')
      expect(ids).to contain_exactly(in_campaign.public_id, other.public_id)
      expect(ids).not_to include(test_candidate.public_id)
    end

    it 'narrows the admin dashboard' do
      get '/api/v1/admin/dashboard', headers: auth_headers(user_with_campaign('admin', campaign))

      expect(response.parsed_body.dig('data', 'candidate_workload', 'total_active_candidates')).to eq(1)
    end

    it 'narrows the MPS dashboard' do
      get '/api/v1/admin/mps_dashboard', headers: auth_headers(user_with_campaign('mps', campaign))

      expect(response.parsed_body.dig('data', 'workflow_stage_queue').sum { |row| row['count'] }).to eq(1)
    end

    it 'narrows the management dashboard' do
      allow(Admin::Reports::ConversionQuery).to receive(:call).and_call_original

      get '/api/v1/admin/management_dashboard', headers: auth_headers(user_with_campaign('management', campaign))

      expect(response).to have_http_status(:ok)
      expect(Admin::Reports::ConversionQuery)
        .to have_received(:call).with(scope: satisfy { |scope| scope.pluck(:id) == [in_campaign.id] })
    end

    it 'narrows reports' do
      get '/api/v1/admin/reports/status_summary', headers: auth_headers(user_with_campaign('mps', campaign))

      expect(response.parsed_body.fetch('data').sum { |row| row['count'] }).to eq(1)
    end
  end
end
