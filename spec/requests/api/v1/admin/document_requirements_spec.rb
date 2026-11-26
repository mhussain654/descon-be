# frozen_string_literal: true

require 'rails_helper'

# Developer-only document checklist editor.
RSpec.describe 'API V1 Admin document requirements', type: :request do
  before { ensure_staff_authorization_reference_data! }

  let(:developer) { create(:user, role: 'developer') }
  let(:document_type) { create(:document_type) }
  let(:country) { create(:country) }

  def headers_for(user, extra = {})
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }.merge(extra)
  end

  def create_requirement(attributes, user: developer)
    post '/api/v1/admin/document_requirements',
         params: { document_requirement: attributes },
         headers: headers_for(user, 'Idempotency-Key' => SecureRandom.uuid), as: :json
  end

  describe 'GET /api/v1/admin/document_requirements' do
    it 'lists every checklist row, the document types and the file types' do
      common = create(:document_requirement, document_type:)
      off = create(:document_requirement, document_type:, country:, active: false)

      get '/api/v1/admin/document_requirements', headers: headers_for(developer)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body.fetch('data')
      rows = data.fetch('requirements').index_by { |row| row['id'] }
      expect(rows.fetch(common.id.to_s)).to include('country' => nil, 'requirement_level' => 'required')
      expect(rows.fetch(off.id.to_s)).to include('active' => false,
                                                 'country' => {
                                                   'code' => country.code, 'name' => country.name_en
                                                 })
      expect(data.fetch('document_types').pluck('code')).to include(document_type.code)
      expect(data.fetch('content_types')).to eq(DocumentRequirement::CONTENT_TYPES)
    end

    it 'is refused to an admin' do
      get '/api/v1/admin/document_requirements', headers: headers_for(create(:user, role: 'admin'))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /api/v1/admin/document_requirements' do
    it "adds a document to a country's checklist" do
      create_requirement({ document_type_code: document_type.code, country_code: country.code,
                           requirement_level: 'optional', instructions_en: ' Bring the original ' })

      expect(response).to have_http_status(:created)
      created = DocumentRequirement.find(response.parsed_body.dig('data', 'id'))
      expect(created).to have_attributes(country:, requirement_level: 'optional', instructions_en: 'Bring the original')
      expect(AuditEvent.where(action_code: 'document_requirement_create', entity_id: created.id)).to exist
    end

    it 'adds a document to the common checklist' do
      create_requirement({ document_type_code: document_type.code, country_code: nil })

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'country')).to be_nil
    end

    it 'refuses a document already in that checklist' do
      create(:document_requirement, document_type:, country:)
      create_requirement({ document_type_code: document_type.code, country_code: country.code })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('document_requirement.document_type_code')
    end

    it 'refuses an unknown document type' do
      create_requirement({ document_type_code: 'missing_type', country_code: nil })

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'is refused to an admin' do
      create_requirement({ document_type_code: document_type.code }, user: create(:user, role: 'admin'))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v1/admin/document_requirements/:id' do
    let!(:requirement) { create(:document_requirement, document_type:, country:) }

    def update_requirement(attributes)
      patch "/api/v1/admin/document_requirements/#{requirement.id}",
            params: { document_requirement: attributes }, headers: headers_for(developer), as: :json
    end

    it 'edits the candidate-facing settings' do
      update_requirement({ requirement_level: 'not_applicable', active: false, maximum_files: 3,
                           accepted_content_types: %w[application/pdf], instructions_ur: 'اصل لائیں',
                           expected_updated_at: requirement.updated_at.utc.iso8601 })

      expect(response).to have_http_status(:ok)
      expect(requirement.reload).to have_attributes(
        requirement_level: 'not_applicable', active: false, maximum_files: 3,
        accepted_content_types: %w[application/pdf], instructions_ur: 'اصل لائیں'
      )
    end

    it 'refuses an unsupported file type' do
      update_requirement({ accepted_content_types: %w[text/plain] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('accepted_content_types')
    end

    it 'refuses a stale edit' do
      update_requirement({ maximum_files: 2, expected_updated_at: 1.day.ago.utc.iso8601 })

      expect(response).to have_http_status(:conflict)
      expect(requirement.reload.maximum_files).to eq(1)
    end
  end
end
