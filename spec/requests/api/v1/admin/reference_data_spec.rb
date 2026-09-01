# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Reference Data', type: :request do
  self.use_transactional_tests = false

  before do
    ensure_staff_authorization_reference_data!
  end

  # Country/Project/Craft are shared reference data other suites' fixtures
  # (e.g. document requirements) may already reference -- unlike the
  # candidate-scoped tables elsewhere, the tables themselves are never wiped
  # here; each example creates its own uniquely-coded rows, asserts on those
  # specifically (tolerating whatever else already exists in the table), and
  # this block only ever deletes rows carrying one of *this spec's own*
  # test-specific codes, so repeated runs never collide on a leftover code
  # from a prior run without touching any other suite's reference data.
  def reference_test_codes
    %w[
      zzz_ref_test aaa_ref_test inactive_ref_test proj_ref_test craft_ref_test
      mps_302_country mps_302_project mps_302_craft
    ]
  end

  def clean_reference_test_data!
    Country.where(code: reference_test_codes).delete_all
    Project.where(code: reference_test_codes).delete_all
    Craft.where(code: reference_test_codes).delete_all
  end

  # Unlike the candidate-scoped specs, this suite never wipes User/Session/
  # AuthenticationEvent/RefreshToken -- those tables are shared with every
  # other suite (candidates created elsewhere hold a `created_by` FK to a
  # User row), and this spec doesn't assert on their contents, so deleting
  # them here only risks an FK violation against unrelated data without
  # buying this suite anything.
  around do |example|
    clean_reference_test_data!
    example.run
  ensure
    clean_reference_test_data!
  end

  def access_token_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def strip_permission!(role_code, permission_code)
    RolePermission.joins(:role, :permission)
                  .find_by!(roles: { code: role_code }, permissions: { code: permission_code })
                  .destroy!
  end

  describe 'GET /api/v1/admin/countries' do
    it 'lists active countries with localized names, ordered by code, excluding inactive ones' do
      actor = create(:user, role: 'mps')
      create(:country, code: 'zzz_ref_test', name_en: 'Zed Country')
      create(:country, code: 'aaa_ref_test', name_en: 'A Country')
      create(:country, code: 'inactive_ref_test', name_en: 'Inactive Country', active: false)

      get '/api/v1/admin/countries', headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:ok)
      data = response.parsed_body.fetch('data')
      codes = data.pluck('code')
      expect(codes).to include('aaa_ref_test', 'zzz_ref_test')
      expect(codes).not_to include('inactive_ref_test')
      expect(codes.index('aaa_ref_test')).to be < codes.index('zzz_ref_test')
      expect(data.find do |item|
        item.fetch('code') == 'aaa_ref_test'
      end).to eq({ 'code' => 'aaa_ref_test', 'name' => 'A Country' })
    end

    it 'is forbidden for a staff role with neither view_candidates nor manage_candidates' do
      strip_permission!('finance', 'view_candidates')
      actor = create(:user, role: 'finance')

      get '/api/v1/admin/countries', headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/admin/projects' do
    it 'lists active projects with localized names' do
      actor = create(:user, role: 'mps')
      create(:project, code: 'proj_ref_test', name_en: 'Test Project')

      get '/api/v1/admin/projects', headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data').pluck('code')).to include('proj_ref_test')
    end
  end

  describe 'GET /api/v1/admin/crafts' do
    it 'lists active crafts with localized names' do
      actor = create(:user, role: 'mps')
      create(:craft, code: 'craft_ref_test', name_en: 'Test Craft')

      get '/api/v1/admin/crafts', headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data').pluck('code')).to include('craft_ref_test')
    end
  end

  describe 'reference-data mutations' do
    it 'creates, updates, and retires a country without deleting its historical identity' do
      actor = create(:user, role: 'hr')
      headers = {
        'Authorization' => "Bearer #{access_token_for(actor)}",
        'Idempotency-Key' => 'reference-country-create'
      }

      post '/api/v1/admin/countries',
           params: { reference_data: { code: 'mps_302_country', name_en: 'MPS Country', name_ur: 'ایم پی ایس ملک' } },
           headers: headers

      expect(response).to have_http_status(:created)
      created = response.parsed_body.fetch('data')
      expect(created).to include('code' => 'mps_302_country', 'active' => true)

      patch '/api/v1/admin/countries/mps_302_country',
            params: { reference_data: {
              name_en: 'Updated Country', expected_updated_at: created.fetch('updated_at')
            } },
            headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:ok)
      updated = response.parsed_body.fetch('data')
      expect(updated.fetch('name')).to eq('Updated Country')

      post '/api/v1/admin/countries/mps_302_country/retirement',
           params: { reference_data: { expected_updated_at: updated.fetch('updated_at') } },
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'active')).to be(false)
      expect(Country.find_by!(code: 'mps_302_country')).not_to be_active
      expect(AuditEvent.where(action_code: 'reference_data_retire').count).to eq(1)
    end

    it 'does not allow a view-only staff member to mutate reference data' do
      actor = create(:user, role: 'mps')

      headers = {
        'Authorization' => "Bearer #{access_token_for(actor)}",
        'Idempotency-Key' => 'reference-forbidden'
      }
      post '/api/v1/admin/projects',
           params: { reference_data: { code: 'mps_302_project', name_en: 'Project', name_ur: 'پروجیکٹ' } },
           headers: headers

      expect(response).to have_http_status(:forbidden)
      expect(Project.find_by(code: 'mps_302_project')).to be_nil
    end
  end
end
