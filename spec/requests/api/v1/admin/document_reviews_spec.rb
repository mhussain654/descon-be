# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Document Reviews', type: :request do
  before do
    ensure_staff_authorization_reference_data!
  end

  def access_token_for(user)
    post '/api/v1/auth/login', params: { auth: { email: user.email, password: 'Password123!' } }
    response.parsed_body.dig('data', 'access_token')
  end

  def candidate_token_for(candidate)
    candidate_session = create(:candidate_session, candidate:)
    CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
  end

  def document_type_for(code)
    DocumentType.find_or_create_by!(code:) do |record|
      record.name_en = code.humanize
      record.name_ur = code.humanize
      record.active = true
      record.requires_number = false
      record.requires_expiry = false
    end
  end

  def create_requirement(assignment:, code:, required: true)
    document_type = document_type_for(code)

    create(
      :document_requirement,
      document_type:,
      country: assignment.country,
      project: assignment.project,
      craft: assignment.craft,
      required:
    )
    document_type
  end

  def create_submission(review_statuses:, optional_statuses: [])
    candidate = create(:candidate)
    assignment = create(:candidate_assignment, candidate:)
    create_submission_documents(assignment:, statuses: review_statuses, required: true, prefix: 'required_doc')
    create_submission_documents(assignment:, statuses: optional_statuses, required: false, prefix: 'optional_doc')

    submit_documents(candidate:, review_statuses:, optional_statuses:)
    find_or_create_submission(assignment:)
  end

  def review_metadata(status_code)
    if %w[uploaded under_verification].include?(status_code)
      return { verified_at: nil, verified_by: nil, rejection_reason: nil }
    end

    {
      verified_at: Time.current,
      verified_by: create(:user, role: 'admin'),
      rejection_reason: status_code == 'rejected' ? 'Document is unreadable.' : nil
    }
  end

  def create_submission_documents(assignment:, statuses:, required:, prefix:)
    statuses.each do |status_code|
      document_type = create_requirement(assignment:, code: "#{prefix}_#{SecureRandom.hex(3)}", required:)
      create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type:,
        status_code:,
        **review_metadata(status_code)
      )
    end
  end

  def submit_documents(candidate:, review_statuses:, optional_statuses:)
    return unless review_statuses.all?('uploaded') && optional_statuses.all?('uploaded')

    Candidates::DocumentSubmissions::SubmitService.call(candidate:, request_id: SecureRandom.uuid)
  end

  def find_or_create_submission(assignment:)
    CandidateDocumentSubmission.find_by(candidate_assignment: assignment) || create_manual_submission(assignment:)
  end

  def create_manual_submission(assignment:)
    submission = create(:candidate_document_submission, candidate_assignment: assignment, submitted_at: Time.current)
    create_submission_items(submission:, assignment:)
    submission
  end

  def create_submission_items(submission:, assignment:)
    assignment.candidate_documents.current_version.order(:id).each do |document|
      create(
        :candidate_document_submission_item,
        candidate_document_submission: submission,
        candidate_document: document,
        requirement_code: document.document_type.code,
        required: document.document_type.code.start_with?('required_')
      )
    end
  end

  describe 'GET /api/v1/admin/document_submissions' do
    it 'lists waiting submissions with pagination and localized safe metadata' do
      actor = create(:user, role: 'admin')
      waiting_submission = create_submission(review_statuses: %w[under_verification verified])
      create_submission(review_statuses: %w[verified])

      get '/api/v1/admin/document_submissions',
          params: { page: { number: 1, size: 1 }, filter: { status: 'partially_reviewed' } },
          headers: { 'Authorization' => "Bearer #{access_token_for(actor)}", 'X-Locale' => 'ur' }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Language']).to eq('ur')
      expect(response.parsed_body.dig('meta', 'pagination')).to eq(
        'page' => 1,
        'per_page' => 1,
        'total_count' => 1,
        'total_pages' => 1
      )
      expect(response.parsed_body.dig('data', 0, 'id')).to eq(waiting_submission.public_id)
      expect(response.parsed_body.dig('data', 0, 'candidate', 'id')).to eq(waiting_submission.candidate.public_id)
      expect(response.parsed_body.dig('data', 0, 'review', 'review_state')).to eq('partially_reviewed')
      expect(response.body).not_to include('/storage/')
    end

    it 'rejects unauthorized roles, inactive staff, and candidate tokens safely' do
      create_submission(review_statuses: %w[under_verification])
      finance_user = create(:user, role: 'finance')

      get '/api/v1/admin/document_submissions',
          headers: { 'Authorization' => "Bearer #{access_token_for(finance_user)}", 'X-Locale' => 'ur' }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('review_not_allowed')

      inactive_user = create(:user, role: 'admin')
      inactive_token = access_token_for(inactive_user)
      inactive_user.update!(active: false)
      get '/api/v1/admin/document_submissions', headers: { 'Authorization' => "Bearer #{inactive_token}" }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('inactive_account')

      candidate = create(:candidate)
      get '/api/v1/admin/document_submissions',
          headers: { 'Authorization' => "Bearer #{candidate_token_for(candidate)}" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/admin/document_submissions/:id' do
    it 'returns safe submission detail by public id only' do
      actor = create(:user, role: 'hr')
      submission = create_submission(review_statuses: %w[under_verification])

      get "/api/v1/admin/document_submissions/#{submission.public_id}",
          headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'id')).to eq(submission.public_id)
      expect(response.parsed_body.dig('data', 'documents', 0, 'id')).to be_present
      expect(response.parsed_body.dig('data', 'documents', 0, 'status')).to eq('pending_review')
      expect(response.parsed_body.dig('data', 'documents', 0)).not_to have_key('storage_key')
      expect(response.parsed_body.dig('data', 'documents', 0)).not_to have_key('internal_id')
    end

    it 'returns a specific not found error for unknown public ids' do
      actor = create(:user, role: 'admin')

      get '/api/v1/admin/document_submissions/unknown-id',
          headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('document_submission_not_found')
    end
  end

  describe 'POST /api/v1/admin/candidate_documents/:id/access' do
    it 'returns a short-lived private access URL and audits access' do
      actor = create(:user, role: 'mps')
      submission = create_submission(review_statuses: %w[under_verification])
      document = submission.candidate_documents.first

      post "/api/v1/admin/candidate_documents/#{document.public_id}/access",
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('private')
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.parsed_body.dig('data', 'document_id')).to eq(document.public_id)
      expect(response.parsed_body.dig('data', 'url')).to include('/rails/active_storage/blobs/proxy/')
      expect(AuditEvent.last.action_code).to eq('candidate_document_accessed')
    end

    it 'returns localized forbidden and missing-attachment errors' do
      finance_user = create(:user, role: 'finance')
      submission = create_submission(review_statuses: %w[under_verification])
      document = submission.candidate_documents.first

      post "/api/v1/admin/candidate_documents/#{document.public_id}/access",
           headers: { 'Authorization' => "Bearer #{access_token_for(finance_user)}", 'X-Locale' => 'ur' }

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('document_access_forbidden')

      actor = create(:user, role: 'admin')
      document.file.purge

      post "/api/v1/admin/candidate_documents/#{document.public_id}/access",
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('document_attachment_missing')
    end
  end

  describe 'POST /api/v1/admin/candidate_documents/:id/verifications' do
    it 'verifies a pending document and replays the same idempotency key after token renewal' do
      actor = create(:user, role: 'admin')
      submission = create_submission(review_statuses: %w[under_verification])
      document = submission.candidate_documents.first
      headers = { 'Authorization' => "Bearer #{access_token_for(actor)}", 'Idempotency-Key' => 'verify-doc-1' }

      post "/api/v1/admin/candidate_documents/#{document.public_id}/verifications", headers: headers
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'document', 'status')).to eq('verified')
      expect(response.parsed_body.dig('data', 'submission', 'review', 'review_state')).to eq('verified')

      post "/api/v1/admin/candidate_documents/#{document.public_id}/verifications",
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}", 'Idempotency-Key' => 'verify-doc-1' }

      expect(response).to have_http_status(:created)
      expect(response.headers['Idempotency-Replayed']).to eq('true')
      expect(AuditEvent.where(action_code: 'candidate_document_verified').count).to eq(1)
    end

    it 'returns review errors for unauthorized, non-pending, and missing documents' do
      finance_user = create(:user, role: 'finance')
      submission = create_submission(review_statuses: %w[under_verification])
      document = submission.candidate_documents.first

      post "/api/v1/admin/candidate_documents/#{document.public_id}/verifications",
           headers: { 'Authorization' => "Bearer #{access_token_for(finance_user)}", 'X-Locale' => 'ur' }
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('review_not_allowed')

      document.update!(status_code: 'verified', verified_by: create(:user, role: 'admin'), verified_at: Time.current)
      actor = create(:user, role: 'admin')
      post "/api/v1/admin/candidate_documents/#{document.public_id}/verifications",
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}", 'Idempotency-Key' => 'verify-doc-2' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('document_already_reviewed')

      post '/api/v1/admin/candidate_documents/unknown-id/verifications',
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}", 'Idempotency-Key' => 'verify-doc-3' }
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('candidate_document_not_found')
    end
  end

  describe 'POST /api/v1/admin/candidate_documents/:id/rejections' do
    it 'rejects a pending document, enforces reason validation, and conflicts on same-key different reason' do
      actor = create(:user, role: 'admin')
      submission = create_submission(review_statuses: %w[under_verification])
      document = submission.candidate_documents.first
      headers = { 'Authorization' => "Bearer #{access_token_for(actor)}", 'Idempotency-Key' => 'reject-doc-1' }

      post "/api/v1/admin/candidate_documents/#{document.public_id}/rejections",
           params: { rejection: { reason: 'Document is unreadable.' } },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('data', 'document', 'status')).to eq('rejected')
      expect(response.parsed_body.dig('data', 'submission', 'review', 'review_state')).to eq('changes_required')

      other_submission = create_submission(review_statuses: %w[under_verification])
      other_document = other_submission.candidate_documents.first
      post "/api/v1/admin/candidate_documents/#{other_document.public_id}/rejections",
           params: { rejection: { reason: 'Different valid reason.' } },
           headers: headers

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('idempotency_conflict')
    end

    it 'returns required and invalid reason errors and rejects already-reviewed documents' do
      actor = create(:user, role: 'admin')
      submission = create_submission(review_statuses: %w[under_verification])
      document = submission.candidate_documents.first
      auth_headers = { 'Authorization' => "Bearer #{access_token_for(actor)}", 'Idempotency-Key' => 'reject-doc-2' }

      post "/api/v1/admin/candidate_documents/#{document.public_id}/rejections",
           params: { rejection: { reason: '   ' } },
           headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('rejection_reason_required')

      post "/api/v1/admin/candidate_documents/#{document.public_id}/rejections",
           params: { rejection: { reason: '<b>too short</b>' } },
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}", 'Idempotency-Key' => 'reject-doc-3' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('rejection_reason_invalid')

      document.update!(status_code: 'verified', verified_by: actor, verified_at: Time.current)
      post "/api/v1/admin/candidate_documents/#{document.public_id}/rejections",
           params: { rejection: { reason: 'Document is unreadable.' } },
           headers: { 'Authorization' => "Bearer #{access_token_for(actor)}", 'Idempotency-Key' => 'reject-doc-4' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('errors', 0, 'code')).to eq('document_already_reviewed')
    end
  end
end
