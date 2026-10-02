# frozen_string_literal: true

require 'rails_helper'

# Multi-file uploads (passport pages, CNIC sides, certificates) against the
# seeded country checklists.
RSpec.describe 'API V1 Candidate Document File Sets', type: :request do
  let(:candidate) { create(:candidate) }
  let!(:assignment) { create(:candidate_assignment, candidate:, country: process_country(:qatar)) }

  before { DocumentChecklists::Seeder.call }

  def headers(extra = {})
    candidate_session = create(:candidate_session, candidate:)
    token = CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
    { 'Authorization' => "Bearer #{token}" }.merge(extra)
  end

  def upload(requirement_code, files)
    post '/api/v1/candidate/documents', headers: headers, params: {
      candidate_document: {
        requirement_code:,
        files: files.map do |name, side_code|
          { file: fixture_upload(name, 'application/octet-stream'), side_code: }.compact
        end
      }
    }
  end

  it 'returns backend-ordered checklist items with instructions and upload rules' do
    get '/api/v1/candidate/documents', headers: headers('X-Locale' => 'ur')

    items = response.parsed_body.fetch('data')
    expect(items.pluck('requirement_code').first(2)).to eq(%w[passport cnic])
    expect(items.pluck('display_position')).to eq(items.pluck('display_position').sort)
    expect(items.first).to include('minimum_files' => 1, 'maximum_files' => 2, 'combined_pdf_allowed' => true,
                                   'allowed_side_codes' => %w[combined page_1 page_2])
    expect(items.first.fetch('instructions')).to include('پاسپورٹ')
  end

  it 'uploads a passport as two images (page 1 and page 2) under one document' do
    upload('passport', [['test.jpg', 'page_1'], ['test.png', 'page_2']])

    expect(response).to have_http_status(:created)
    files = response.parsed_body.dig('data', 'document', 'files')
    expect(files.map { |file| file.slice('side_code', 'position', 'content_type') }).to eq(
      [{ 'side_code' => 'page_1', 'position' => 1, 'content_type' => 'image/jpeg' },
       { 'side_code' => 'page_2', 'position' => 2, 'content_type' => 'image/png' }]
    )
    expect(assignment.candidate_documents.current_version.sole.files.count).to eq(2)
  end

  it 'uploads a passport as one combined PDF, labelling a lone legacy file as combined' do
    post '/api/v1/candidate/documents', headers: headers, params: {
      candidate_document: { requirement_code: 'passport', file: fixture_upload('test.pdf', 'application/pdf') }
    }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data', 'document', 'files', 0, 'side_code')).to eq('combined')
  end

  it 'rejects a CNIC front without its back, storing nothing' do
    expect { upload('cnic', [['test.jpg', 'front']]) }.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0)).to include(
      'code' => 'invalid_document_files', 'field' => 'candidate_document.files',
      'details' => { 'reason' => 'incomplete_side_pair', 'missing_side_code' => 'back' }
    )
    expect(CandidateDocument.count).to eq(0)
  end

  it 'rejects a file whose content is not a PDF or image, whatever it is called or declared as' do
    upload('cv', [['not_pdf.txt', nil]])

    expect(response.parsed_body.dig('errors', 0)).to include('code' => 'unsupported_file_type',
                                                             'field' => 'candidate_document.files[0].file')
  end

  it 'rejects a file flagged by the malware scanning hook before anything is stored' do
    allow(Candidates::Documents::MalwareScanner).to receive(:call).and_raise(MalwareDetectedError)

    expect { upload('cv', [['test.pdf', nil]]) }.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('malware_detected')
    expect(CandidateDocument.count).to eq(0)
  end

  it 'accepts several certificates under one requirement' do
    upload('educational_certificates', [['test.pdf', nil], ['test.jpg', nil], ['test.png', nil]])

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data', 'document', 'files').pluck('side_code')).to all(eq('certificate'))
  end

  it 'versions a replacement as a whole new file set' do
    upload('cnic', [['test.jpg', 'front'], ['test.png', 'back']])
    first = assignment.candidate_documents.current_version.sole

    upload('cnic', [['test.pdf', 'combined']])

    expect(response).to have_http_status(:created)
    expect(first.reload.superseded_at).to be_present
    expect(first.files.count).to eq(2)
    expect(assignment.candidate_documents.current_version.sole.files.map(&:side_code)).to eq(%w[combined])
  end

  it 'serves each file of a document through its own short-lived access URL, only for its owner' do
    upload('passport', [['test.jpg', 'page_1'], ['test.png', 'page_2']])
    document_id = response.parsed_body.dig('data', 'document', 'id')
    second_file_id = response.parsed_body.dig('data', 'document', 'files', 1, 'id')

    post "/api/v1/candidate/documents/#{document_id}/access", params: { file_id: second_file_id }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'file_id')).to eq(second_file_id)
    expect(response.parsed_body.dig('data', 'url')).to include('test.png')

    post "/api/v1/candidate/documents/#{document_id}/access", params: { file_id: SecureRandom.uuid }, headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
