# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Candidate Documents', type: :request do
  def existing_or_create_document_type(code)
    DocumentType.find_or_create_by!(code:) do |document_type|
      document_type.name_en = code.humanize
      document_type.name_ur = code.humanize
      document_type.active = true
      document_type.requires_number = false
      document_type.requires_expiry = false
    end
  end

  def candidate_auth_headers(candidate, extra_headers = {})
    { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }.merge(extra_headers)
  end

  def candidate_access_token_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
  end

  def candidate_assignment_for(candidate)
    candidate.current_assignment || create(:candidate_assignment, candidate:)
  end

  def create_requirement(candidate:, code: 'passport', required: true)
    assignment = candidate_assignment_for(candidate)
    document_type = existing_or_create_document_type(code)
    create_requirement_record(assignment:, document_type:, required:)
    document_type
  end

  def create_requirement_record(assignment:, document_type:, required:)
    create(
      :document_requirement,
      document_type:,
      country: assignment.country,
      project: assignment.project,
      craft: assignment.craft,
      required:
    )
  end

  def pcc_code
    CandidateDocument::PCC_REQUIREMENT_CODE
  end

  def checklist_item_for(response_body, requirement_code)
    response_body.fetch('data').find { |entry| entry['requirement_code'] == requirement_code }
  end

  describe 'GET /api/v1/candidate/documents' do
    it 'returns the authenticated candidate checklist with missing requirements only for that candidate' do
      candidate = create(:candidate)
      other_candidate = create(:candidate)
      create_requirement(candidate:, code: 'passport')
      other_type = create_requirement(candidate: other_candidate, code: 'cv')
      other_document = create(
        :candidate_document,
        candidate_assignment: other_candidate.current_assignment,
        document_type: other_type
      )

      get '/api/v1/candidate/documents', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:ok)
      item = checklist_item_for(response.parsed_body, 'passport')
      expect(item).to be_present
      expect(item['status']).to eq('missing')
      expect(response.body).not_to include(other_document.public_id)
    end

    it 'returns uploaded document metadata without internal ids or storage paths' do
      candidate = create(:candidate)
      document_type = create_requirement(candidate:, code: 'passport')
      document = create(:candidate_document, candidate_assignment: candidate.current_assignment, document_type:)

      get '/api/v1/candidate/documents', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:ok)
      item = checklist_item_for(response.parsed_body, 'passport')
      expect(item['status']).to eq('uploaded')
      expect(item.dig('document', 'id')).to eq(document.public_id)
      expect(item.dig('document', 'id')).not_to eq(document.id.to_s)
      expect(item.fetch('document').keys).to contain_exactly(
        'id',
        'file_name',
        'content_type',
        'file_size',
        'uploaded_at'
      )
      expect(response.body).not_to include('/storage/')
    end

    it 'returns PCC metadata and compliance status for police character documents' do
      candidate = create(:candidate)
      document_type = create_requirement(candidate:, code: pcc_code)
      document = create(
        :candidate_document,
        candidate_assignment: candidate.current_assignment,
        document_type:,
        issued_on: Date.new(2026, 8, 1)
      )

      get '/api/v1/candidate/documents', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:ok)
      item = checklist_item_for(response.parsed_body, pcc_code)
      expect(item.dig('document', 'id')).to eq(document.public_id)
      expect(item.dig('document', 'issued_on')).to eq('2026-08-01')
      expect(item.dig('document', 'expires_on')).to eq('2027-02-01')
      expect(item.dig('document', 'compliance_status')).to eq('current')
    end

    it 'returns the rejection reason and review date for a rejected document' do
      candidate = create(:candidate)
      document_type = create_requirement(candidate:, code: 'passport')
      create(
        :candidate_document,
        candidate_assignment: candidate.current_assignment,
        document_type:,
        status_code: 'rejected',
        verified_by: create(:user),
        verified_at: Time.zone.parse('2026-08-20T10:00:00Z'),
        rejection_reason: 'Document is unreadable.'
      )

      get '/api/v1/candidate/documents', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:ok)
      item = checklist_item_for(response.parsed_body, 'passport')
      expect(item['status']).to eq('rejected')
      expect(item.dig('document', 'rejection_reason')).to eq('Document is unreadable.')
      expect(item.dig('document', 'reviewed_at')).to eq('2026-08-20T10:00:00Z')
    end

    it 'returns the review date without a rejection reason for a verified document' do
      candidate = create(:candidate)
      document_type = create_requirement(candidate:, code: 'passport')
      create(
        :candidate_document,
        candidate_assignment: candidate.current_assignment,
        document_type:,
        status_code: 'verified',
        verified_by: create(:user),
        verified_at: Time.zone.parse('2026-08-20T10:00:00Z')
      )

      get '/api/v1/candidate/documents', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:ok)
      item = checklist_item_for(response.parsed_body, 'passport')
      expect(item.dig('document', 'reviewed_at')).to eq('2026-08-20T10:00:00Z')
      expect(item['document']).not_to have_key('rejection_reason')
    end

    it 'omits the rejection reason and review date for a document that has not been reviewed' do
      candidate = create(:candidate)
      document_type = create_requirement(candidate:, code: 'passport')
      create(:candidate_document, candidate_assignment: candidate.current_assignment, document_type:)

      get '/api/v1/candidate/documents', headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:ok)
      item = checklist_item_for(response.parsed_body, 'passport')
      expect(item.fetch('document')).not_to have_key('rejection_reason')
      expect(item.fetch('document')).not_to have_key('reviewed_at')
    end

    it 'rejects inactive candidates and staff tokens' do
      inactive_candidate = create(:candidate, active: false)

      get '/api/v1/candidate/documents',
          headers: { 'Authorization' => "Bearer #{candidate_access_token_for(inactive_candidate)}" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')

      ensure_staff_authorization_reference_data!
      user = create(:user, role: 'admin', password: 'Password123!')
      post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }

      get '/api/v1/candidate/documents',
          headers: { 'Authorization' => "Bearer #{response.parsed_body.dig('data', 'access_token')}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/candidate/documents' do
    it 'uploads valid PDF, PNG, and JPEG documents' do
      candidate = create(:candidate)
      create_requirement(candidate:, code: 'passport')

      {
        'test.pdf' => 'application/pdf',
        'test.png' => 'image/png',
        'test.jpg' => 'image/jpeg'
      }.each do |fixture_name, content_type|
        post '/api/v1/candidate/documents',
             params: {
               candidate_document: {
                 requirement_code: 'passport',
                 file: fixture_upload(fixture_name, content_type)
               }
             },
             headers: { 'Authorization' => "Bearer #{candidate_access_token_for(candidate)}" }

        expect(response).to have_http_status(:created)
        expect(response.parsed_body.dig('data', 'status')).to eq('uploaded')

        CandidateDocument.current_version.last.update!(superseded_at: Time.current)
      end
    end

    it 'supports idempotent retries and rejects same-key reuse with different content' do
      candidate = create(:candidate)
      create_requirement(candidate:, code: 'passport')
      headers = {
        'Authorization' => "Bearer #{candidate_access_token_for(candidate)}",
        'Idempotency-Key' => 'candidate-doc-1'
      }

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: 'passport',
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: headers
      first_document_id = response.parsed_body.dig('data', 'document', 'id')

      expect do
        post '/api/v1/candidate/documents',
             params: {
               candidate_document: {
                 requirement_code: 'passport',
                 file: fixture_upload('test.pdf', 'application/pdf')
               }
             },
             headers: headers
      end.not_to change(CandidateDocument, :count)

      expect(response).to have_http_status(:created)
      expect(response.headers['Idempotency-Replayed']).to eq('true')
      expect(response.parsed_body.dig('data', 'document', 'id')).to eq(first_document_id)

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: 'passport',
               file: fixture_upload('test.png', 'image/png')
             }
           },
           headers: headers

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('idempotency_conflict')
    end

    it 'requires issue date for PCC uploads, rejects bad dates, and rejects client-supplied expiry' do
      candidate = create(:candidate)
      create_requirement(candidate:, code: pcc_code)
      auth_header = candidate_auth_headers(candidate, 'X-Locale' => 'ur')

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: pcc_code,
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: auth_header
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('validation_failed')
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_document.issued_on')
      expect(response.headers['Content-Language']).to eq('ur')

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: pcc_code,
               issued_on: '2026-02-30',
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: candidate_auth_headers(candidate)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_document.issued_on')

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: pcc_code,
               issued_on: '2026-09-01',
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: candidate_auth_headers(candidate)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_document.issued_on')

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: pcc_code,
               issued_on: '2026-08-01',
               expires_on: '2027-02-01',
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: candidate_auth_headers(candidate)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('pcc_expiry_not_editable')
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_document.expires_on')

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: pcc_code,
               issued_on: '2026-08-01',
               expires_on: '',
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: candidate_auth_headers(candidate)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('pcc_expiry_not_editable')
      expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_document.expires_on')
    end

    it 'uploads PCC with derived expiry and conflicts on same idempotency key with different issue date' do
      candidate = create(:candidate)
      create_requirement(candidate:, code: pcc_code)
      headers = candidate_auth_headers(candidate, 'Idempotency-Key' => 'candidate-doc-pcc-1')

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: pcc_code,
               issued_on: '2026-08-01',
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'document', 'issued_on')).to eq('2026-08-01')
      expect(response.parsed_body.dig('data', 'document', 'expires_on')).to eq('2027-02-01')

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: pcc_code,
               issued_on: '2026-08-01',
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: headers
      expect(response).to have_http_status(:created)
      expect(response.headers['Idempotency-Replayed']).to eq('true')

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: pcc_code,
               issued_on: '2026-08-02',
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: headers
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('idempotency_conflict')
    end

    it 'does not persist issue or expiry dates for non-PCC uploads' do
      candidate = create(:candidate)
      document_type = create_requirement(candidate:, code: 'passport')

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: 'passport',
               issued_on: '2026-08-01',
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:created)
      document = CandidateDocument.current_version.find_by!(
        candidate_assignment: candidate.current_assignment,
        document_type:
      )
      expect(document.issued_on).to be_nil
      expect(document.expires_on).to be_nil
      expect(response.parsed_body.dig('data', 'document')).not_to have_key('issued_on')
      expect(response.parsed_body.dig('data', 'document')).not_to have_key('expires_on')
    end

    it 'replays the original upload result when the same candidate retries with a renewed access token' do
      candidate = create(:candidate)
      create_requirement(candidate:, code: 'passport')
      idempotency_headers = { 'Idempotency-Key' => 'candidate-doc-renewed-token' }

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: 'passport',
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: candidate_auth_headers(candidate, idempotency_headers)
      first_document_id = response.parsed_body.dig('data', 'document', 'id')

      expect do
        post '/api/v1/candidate/documents',
             params: {
               candidate_document: {
                 requirement_code: 'passport',
                 file: fixture_upload('test.pdf', 'application/pdf')
               }
             },
             headers: candidate_auth_headers(candidate, idempotency_headers)
      end.not_to change(CandidateDocument, :count)

      expect(response).to have_http_status(:created)
      expect(response.headers['Idempotency-Replayed']).to eq('true')
      expect(response.parsed_body.dig('data', 'document', 'id')).to eq(first_document_id)
    end

    it 'rejects missing, empty, oversized, unsupported, and invalid requirement uploads with localized errors' do
      candidate = create(:candidate)
      create_requirement(candidate:, code: 'passport')
      auth_header = candidate_auth_headers(candidate)

      post '/api/v1/candidate/documents',
           params: { candidate_document: { requirement_code: 'passport' } },
           headers: auth_header
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_file')

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: 'passport',
               file: fixture_upload('empty.pdf', 'application/pdf')
             }
           },
           headers: auth_header
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('empty_file')
    end

    it 'returns missing_file instead of raising when an idempotency key is present without a file' do
      candidate = create(:candidate)
      create_requirement(candidate:, code: 'passport')

      post '/api/v1/candidate/documents',
           params: { candidate_document: { requirement_code: 'passport' } },
           headers: candidate_auth_headers(candidate, 'Idempotency-Key' => 'candidate-doc-missing-file')

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('missing_file')
    end

    it 'rejects oversized uploads' do
      candidate = create(:candidate)
      create_requirement(candidate:, code: 'passport')
      auth_header = candidate_auth_headers(candidate)

      stub_const("#{Candidates::Documents::UploadService}::MAX_FILE_BYTES", 10)
      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: 'passport',
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: auth_header
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('file_too_large')
    end

    it 'rejects unsupported file types' do
      candidate = create(:candidate)
      create_requirement(candidate:, code: 'passport')
      auth_header = candidate_auth_headers(candidate)

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: 'passport',
               file: fixture_upload('not_pdf.txt', 'text/plain')
             }
           },
           headers: auth_header
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unsupported_file_type')
    end

    it 'rejects invalid requirements with localized messages' do
      candidate = create(:candidate)
      create_requirement(candidate:, code: 'passport')
      auth_header = candidate_auth_headers(candidate, 'X-Locale' => 'ur')

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: 'unknown_requirement',
               file: fixture_upload('test.pdf', 'application/pdf')
             }
           },
           headers: auth_header
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('invalid_requirement')
      expect(response.headers['Content-Language']).to eq('ur')
    end

    it 'allows replacement for uploaded documents and forbids replacement for verified documents' do
      candidate = create(:candidate)
      document_type = create_requirement(candidate:, code: 'passport')
      create(
        :candidate_document,
        candidate_assignment: candidate.current_assignment,
        document_type:,
        status_code: 'uploaded'
      )

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: 'passport',
               file: fixture_upload('test.png', 'image/png')
             }
           },
           headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:created)
      expect(
        CandidateDocument.current_version
          .where(candidate_assignment: candidate.current_assignment, document_type:)
          .count
      ).to eq(1)

      CandidateDocument.current_version.last.update!(
        status_code: 'verified',
        verified_by: create(:user),
        verified_at: Time.current
      )

      post '/api/v1/candidate/documents',
           params: {
             candidate_document: {
               requirement_code: 'passport',
               file: fixture_upload('test.jpg', 'image/jpeg')
             }
           },
           headers: candidate_auth_headers(candidate)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('replacement_not_allowed')
    end
  end
end
