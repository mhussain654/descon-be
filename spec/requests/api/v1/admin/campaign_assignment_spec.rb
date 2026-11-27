# frozen_string_literal: true

require 'rails_helper'
require 'csv'

# Phase 3 of campaigns: every import and every new candidate goes into a campaign.
RSpec.describe 'API V1 Admin candidate campaign assignment', type: :request do
  before do
    ensure_staff_authorization_reference_data!
    ensure_candidate_import_reference_data!
  end

  let(:actor) { create(:user, role: 'hr') }
  let(:qatar) { Country.find_by!(code: 'qatar') }
  let(:campaign) { create(:campaign, country: qatar) }
  let(:row) do
    {
      'full_name' => 'Campaign Candidate', 'cnic' => '42101-1234567-1', 'mobile_number' => '+923001234567',
      'registration_number' => '700001', 'preferred_locale' => 'en', 'candidate_status' => 'registered',
      'workflow_stage_code' => 'registered', 'project_code' => 'qatar_infrastructure',
      'craft_code' => 'electrician', 'active' => 'true', 'template_version' => 'v1'
    }
  end

  def headers(user = actor, extra = {})
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }.merge(extra)
  end

  def csv_file(country_code: 'qatar')
    header = Admin::Candidates::Imports::CsvFileParser::SUPPORTED_HEADERS
    values = row.merge('country_code' => country_code)
    tempfile = Tempfile.new(['campaign-import', '.csv'])
    tempfile.write(CSV.generate { |csv| csv << header << header.map { |name| values.fetch(name, '') } })
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, 'text/csv', original_filename: 'campaign-import.csv')
  end

  def preflight(campaign_id:, file: csv_file)
    post '/api/v1/admin/candidate_imports/preflight',
         params: { candidate_import: { campaign_id: campaign_id, file: } }, headers: headers
  end

  describe 'import' do
    it 'requires a campaign' do
      preflight(campaign_id: '')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_import.campaign_id')
    end

    it 'puts the imported candidates in the chosen campaign' do
      preflight(campaign_id: campaign.public_id)
      expect(response.parsed_body.dig('data', 'campaign', 'id')).to eq(campaign.public_id)
      import_id = response.parsed_body.dig('data', 'import_id')

      Admin::Candidates::Imports::CommitService.call(
        actor:, token: response.parsed_body.dig('data', 'preflight_token'), request_id: 'commit-campaign'
      )
      Admin::Candidates::Imports::BatchExecutionService.call(import_id:, request_id: 'run-campaign')

      expect(CandidateAssignment.find_by!(registration_number: 700_001).campaign).to eq(campaign)
      expect(CandidateImportBatch.find_by!(public_id: import_id).campaign).to eq(campaign)
    end

    it "rejects rows for another country than the campaign's" do
      preflight(campaign_id: campaign.public_id, file: csv_file(country_code: 'saudi_arabia'))

      expect(response.parsed_body.dig('data', 'errors')).to include(
        hash_including('field' => 'country_code', 'code' => 'country_not_in_campaign')
      )
    end

    it 'lets the Test campaign take any country' do
      preflight(campaign_id: create(:campaign, :test).public_id, file: csv_file(country_code: 'saudi_arabia'))

      expect(response.parsed_body.dig('data', 'accepted_rows')).to eq(1)
    end

    it 'narrows import history to the working campaign' do
      in_campaign = create(:candidate_import_batch, actor:, campaign: campaign)
      create(:candidate_import_batch, actor:, campaign: create(:campaign))
      actor.update!(selected_campaign: campaign)

      get '/api/v1/admin/candidate_imports', headers: headers

      expect(response.parsed_body.fetch('data').pluck('id')).to eq([in_campaign.public_id])
    end
  end

  describe 'New candidate' do
    def create_params(overrides = {})
      { full_name: 'Form Candidate', cnic: '42101-7654321-1', mobile_number: '+923007654321', preferred_locale: 'en',
        country_code: 'qatar', project_code: 'qatar_infrastructure', craft_code: 'electrician',
        registration_number: '700002', campaign_id: campaign.public_id }.merge(overrides)
    end

    def create_candidate(overrides = {})
      post '/api/v1/admin/candidates', params: { candidate: create_params(overrides) },
                                       headers: headers(actor, 'Idempotency-Key' => SecureRandom.uuid)
    end

    it 'puts the candidate in the chosen campaign' do
      create_candidate

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'assignment', 'campaign', 'id')).to eq(campaign.public_id)
    end

    it 'requires a campaign' do
      create_candidate(campaign_id: '')

      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('campaign_id')
    end

    it "refuses a country other than the campaign's" do
      create_candidate(country_code: 'saudi_arabia')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('country_code')
    end
  end

  describe 'moving a candidate to another campaign' do
    let(:candidate) { create(:candidate) }

    def move_to(target, stage: 'registered')
      create(:candidate_assignment, candidate:, country: qatar, campaign:,
                                    current_workflow_stage: WorkflowStage.find_by!(code: stage))
      patch "/api/v1/admin/candidates/#{candidate.public_id}", params: { candidate: { campaign_id: target.public_id } },
                                                               headers: headers
    end

    it 'moves it while the assignment can still change' do
      target = create(:campaign, country: qatar)

      move_to(target)

      expect(response).to have_http_status(:ok)
      expect(candidate.current_assignment.reload.campaign).to eq(target)
    end

    it 'refuses a campaign of another country' do
      move_to(create(:campaign))

      expect(response.parsed_body.dig('errors', 0)).to include('field' => 'campaign_id')
    end

    it 'is locked once documents were uploaded' do
      move_to(create(:campaign, country: qatar), stage: 'documents_uploaded')

      expect(response.parsed_body.dig('errors', 0)).to include('code' => 'candidate_assignment_field_locked',
                                                               'field' => 'campaign_id')
    end
  end
end
