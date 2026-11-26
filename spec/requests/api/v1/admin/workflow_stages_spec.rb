# frozen_string_literal: true

require 'rails_helper'

# Developer-only workflow stage names and the read-only process view.
RSpec.describe 'API V1 Admin workflow stages and processes', type: :request do
  before { ensure_staff_authorization_reference_data! }

  let(:developer) { create(:user, role: 'developer') }
  let(:stage) { WorkflowStage.find_by!(code: 'medical_fit') }

  def headers_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
  end

  def rename(names, user: developer)
    patch "/api/v1/admin/workflow_stages/#{stage.code}", params: { workflow_stage: names }, headers: headers_for(user),
                                                         as: :json
  end

  describe 'GET /api/v1/admin/workflow_stages' do
    it 'lists stages in order with their built-in names' do
      get '/api/v1/admin/workflow_stages', headers: headers_for(developer)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body.fetch('data')
      expect(data.pluck('position')).to eq(data.pluck('position').sort)
      expect(data.find { |row| row['code'] == 'medical_fit' })
        .to include('name_en' => nil,
                    'default_name_en' => I18n.t('reference_data.workflow_stages.medical_fit',
                                                locale: :en))
    end

    it 'is refused to an admin' do
      get '/api/v1/admin/workflow_stages', headers: headers_for(create(:user, role: 'admin'))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v1/admin/workflow_stages/:code' do
    it 'sets custom names that replace the built-in ones everywhere' do
      rename({ name_en: ' Medically fit ', name_ur: 'طبی طور پر فٹ' })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'name')).to eq('Medically fit')
      expect(stage.reload.name_for(locale: :en)).to eq('Medically fit')
      expect(stage.name_for(locale: :ur)).to eq('طبی طور پر فٹ')
      expect(AuditEvent.where(action_code: 'workflow_stage_rename', entity_id: stage.id)).to exist
    end

    it 'goes back to the built-in name when cleared' do
      stage.update!(name_en: 'Old custom')
      rename({ name_en: '', name_ur: '' })

      expect(response).to have_http_status(:ok)
      expect(stage.reload.name_en).to be_nil
      expect(stage.name_for(locale: :en)).to eq(I18n.t('reference_data.workflow_stages.medical_fit', locale: :en))
    end

    it 'refuses a name that is too long' do
      rename({ name_en: 'x' * 121, name_ur: '' })

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'is refused to an admin' do
      rename({ name_en: 'Nope', name_ur: '' }, user: create(:user, role: 'admin'))

      expect(response).to have_http_status(:forbidden)
      expect(stage.reload.name_en).to be_nil
    end
  end

  describe 'GET /api/v1/admin/mobilization_processes' do
    it 'lists the active processes with their ordered stages' do
      get '/api/v1/admin/mobilization_processes', headers: headers_for(developer)

      expect(response).to have_http_status(:ok)
      qatar = response.parsed_body.fetch('data').find { |process| process.dig('country', 'code') == 'qatar' }
      expect(qatar).to include('status' => 'active')
      positions = qatar.fetch('stages').pluck('position')
      expect(positions).to eq(positions.sort)
      expect(qatar.fetch('stages').first).to include('code', 'name', 'required')
    end

    it 'is refused to an admin' do
      get '/api/v1/admin/mobilization_processes', headers: headers_for(create(:user, role: 'admin'))

      expect(response).to have_http_status(:forbidden)
    end
  end
end
