# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'candidate import preflight and commit' do
  before { ensure_candidate_import_reference_data! }

  let(:actor) { create(:user, role: 'hr') }

  def upload(rows)
    content = CSV.generate do |csv|
      csv << Admin::Candidates::Imports::CsvFileParser::SUPPORTED_HEADERS
      rows.each { |row| csv << row }
    end
    tempfile = Tempfile.new(['candidate-import', '.csv'])
    tempfile.write(content)
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, 'text/csv', original_filename: 'candidate-import-template-v1.csv')
  end

  def valid_row(**overrides)
    values = {
      'full_name' => 'Imported Candidate', 'cnic' => '42101-1234567-1', 'mobile_number' => '+923001234567',
      'reference_number' => 'DES-001001', 'preferred_locale' => 'en', 'candidate_status' => 'registered',
      'workflow_stage_code' => 'registered', 'country_code' => 'qatar', 'project_code' => 'qatar_infrastructure',
      'craft_code' => 'electrician', 'active' => 'true', 'passport_number' => 'AB123456',
      'next_of_kin_name' => '', 'next_of_kin_relationship' => '', 'next_of_kin_mobile_number' => '',
      'next_of_kin_cnic' => '', 'template_version' => 'v1'
    }.merge(overrides.stringify_keys)
    Admin::Candidates::Imports::CsvFileParser::SUPPORTED_HEADERS.map { |header| values.fetch(header) }
  end

  it 'commits only the persisted accepted snapshot' do
    preflight = Admin::Candidates::Imports::PreflightService.call(actor:, file: upload([valid_row]), request_id: 'preflight-1')

    expect(preflight).to include(accepted_rows: 1, rejected_rows: 0)

    result = Admin::Candidates::Imports::CommitService.call(
      actor:, token: preflight.fetch(:preflight_token), request_id: 'commit-1'
    )

    expect(result).to include(status: 'committed', imported_rows: 1)
    expect(Candidate.find_by!(cnic: '42101-1234567-1').candidate_assignments.find_by!(reference_number: 'DES-001001')).to be_present
  end

  it 'returns field-addressable errors for partial next-of-kin data without scheduling the row' do
    result = Admin::Candidates::Imports::PreflightService.call(
      actor:, file: upload([valid_row('next_of_kin_name' => 'Relative')]), request_id: 'preflight-kin'
    )

    expect(result).to include(accepted_rows: 0, rejected_rows: 1)
    expect(result.fetch(:errors)).to include(hash_including(field: 'next_of_kin_relationship', code: 'incomplete_next_of_kin'))
  end

  it 'returns the completed result for an identical commit replay without duplicating candidates' do
    preflight = Admin::Candidates::Imports::PreflightService.call(actor:, file: upload([valid_row]), request_id: 'preflight-replay')
    first = Admin::Candidates::Imports::CommitService.call(actor:, token: preflight.fetch(:preflight_token), request_id: 'commit-replay')
    second = Admin::Candidates::Imports::CommitService.call(actor:, token: preflight.fetch(:preflight_token), request_id: 'commit-replay')

    expect(second).to include(status: 'committed', imported_rows: first.fetch(:imported_rows))
    expect(Candidate.where(cnic: '42101-1234567-1').count).to eq(1)
  end
end
