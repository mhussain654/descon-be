# frozen_string_literal: true

require 'rails_helper'

# Uploads against the seeded country checklists: every document is a scanned
# PDF -- a passport or CNIC as one PDF holding both pages/sides, certificates
# as one or more PDFs.
RSpec.describe 'API V1 Candidate Document File Sets', type: :request do
  let(:candidate) { create(:candidate) }
  let!(:assignment) { create(:candidate_assignment, candidate:, country: process_country(:qatar)) }

  before { DocumentChecklists::Seeder.call }

  def headers(extra = {})
    candidate_session = create(:candidate_session, candidate:)
    token = CandidateAuthentication::TokenIssuer.call(candidate:, candidate_session:)
    { 'Authorization' => "Bearer #{token}" }.merge(extra)
  end

  def upload(requirement_code, files, extra = {})
    post '/api/v1/candidate/documents', headers: headers, params: {
      candidate_document: {
        requirement_code:,
        **extra,
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
    expect(items.first).to include('minimum_files' => 1, 'maximum_files' => 1, 'combined_pdf_allowed' => true,
                                   'allowed_side_codes' => %w[combined],
                                   'accepted_content_types' => %w[application/pdf])
    expect(items.first.fetch('instructions')).to include('پاسپورٹ')
  end

  it 'rejects a passport photo -- documents are scanned PDFs only -- storing nothing' do
    expect { upload('passport', [['test.jpg', 'combined']]) }.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('unsupported_file_type')
  end

  it 'uploads a passport as one combined PDF, labelling a lone legacy file as combined' do
    post '/api/v1/candidate/documents', headers: headers, params: {
      candidate_document: { requirement_code: 'passport', file: fixture_upload('test.pdf', 'application/pdf') }
    }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data', 'document', 'files', 0, 'side_code')).to eq('combined')
  end

  it 'rejects a CNIC sent as separate sides -- it is one PDF holding both -- storing nothing' do
    expect { upload('cnic', [['test.pdf', 'front'], ['test.pdf', 'back']]) }.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0)).to include('code' => 'invalid_document_files',
                                                             'field' => 'candidate_document.files')
    expect(CandidateDocument.count).to eq(0)
  end

  it "requires the next of kin's relation, keeps it on the document, and asks a wife's marriage certificate" do
    upload('next_of_kin_cnic', [['test.pdf', 'combined']])
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0, 'field')).to eq('candidate_document.next_of_kin_relation')

    upload('next_of_kin_cnic', [['test.pdf', 'combined']], next_of_kin_relation: 'cousin')
    expect(response).to have_http_status(:unprocessable_content)

    upload('next_of_kin_cnic', [['test.pdf', 'combined']], next_of_kin_relation: 'wife')
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data', 'document', 'next_of_kin_relation')).to eq('wife')

    get '/api/v1/candidate/documents', headers: headers
    expect(response.parsed_body.fetch('data').pluck('requirement_code')).to include('marriage_certificate')
  end

  it 'refuses a PCC issued more than 5 months ago' do
    upload('police_character', [['test.pdf', nil]], issued_on: (5.months.ago.to_date - 1.day).iso8601)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig('errors', 0)).to include('field' => 'candidate_document.issued_on')
    expect(response.parsed_body.dig('errors', 0, 'message')).to include('more than 5 months ago')

    upload('police_character', [['test.pdf', nil]], issued_on: 5.months.ago.to_date.iso8601)
    expect(response).to have_http_status(:created)
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

  it 'refuses document uploads with 503 when no malware scanner is available (fail closed), storing nothing' do
    unavailable = instance_double(MalwareScanning::Configuration, provider: nil, scanner_code: nil,
                                                                  deployment_environment: 'production')
    allow(MalwareScanning::Configuration).to receive(:new).and_return(unavailable)

    expect { upload('cv', [['test.pdf', nil]]) }.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.dig('errors', 0, 'code')).to eq('malware_scan_unavailable')
  end

  it 'accepts several certificates under one requirement' do
    upload('educational_certificates', [['test.pdf', nil], ['test.pdf', nil], ['test.pdf', nil]])

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('data', 'document', 'files').pluck('side_code')).to all(eq('certificate'))
  end

  it 'versions a replacement as a whole new file set' do
    upload('educational_certificates', [['test.pdf', nil], ['test.pdf', nil]])
    first = assignment.candidate_documents.current_version.sole

    upload('educational_certificates', [['test.pdf', nil]])

    expect(response).to have_http_status(:created)
    expect(first.reload.superseded_at).to be_present
    expect(first.files.count).to eq(2)
    expect(assignment.candidate_documents.current_version.sole.files.map(&:side_code)).to eq(%w[certificate])
  end

  it 'serves each file of a document through its own short-lived access URL, only for its owner' do
    upload('educational_certificates', [['test.pdf', nil], ['test.pdf', nil]])
    document_id = response.parsed_body.dig('data', 'document', 'id')
    second_file_id = response.parsed_body.dig('data', 'document', 'files', 1, 'id')

    post "/api/v1/candidate/documents/#{document_id}/access", params: { file_id: second_file_id }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'file_id')).to eq(second_file_id)
    expect(response.parsed_body.dig('data', 'url')).to include('test.pdf')

    post "/api/v1/candidate/documents/#{document_id}/access", params: { file_id: SecureRandom.uuid }, headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
