# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::Candidates::ImportService do
  let(:actor) { create(:user, role: 'hr') }

  before do
    ensure_candidate_import_reference_data!
  end

  def uploaded_csv(content, filename: 'candidates.csv', content_type: 'text/csv')
    tempfile = Tempfile.new([File.basename(filename, '.csv'), '.csv'])
    tempfile.write(content)
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, content_type, original_filename: filename)
  end

  def csv_content(*rows)
    CSV.generate do |csv|
      csv << %w[
        full_name
        cnic
        mobile_number
        reference_number
        preferred_locale
        candidate_status
        workflow_stage_code
        country_code
        project_code
        craft_code
        active
      ]
      rows.each { |row| csv << row }
    end
  end

  describe '.call' do
    it 'imports valid rows and creates candidate assignments in one pass' do
      result = described_class.call(
        actor:,
        file: uploaded_csv(
          csv_content(
            ['Candidate One', '42101-1234567-1', '+923001234567', 'DES-001001', 'en', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true'],
            ['Candidate Two', '42102-1234567-2', '+923001234568', 'DES-001002', 'ur', 'registered', 'documents_pending', 'uae',
             'qatar_energy', 'welder', 'inactive']
          )
        ),
        request_id: 'req-import-1'
      )

      expect(result).to include(successful_rows: 2, failed_rows: 0, skipped_rows: 0, total_rows: 2)
      expect(Candidate.count).to eq(2)
      expect(CandidateAssignment.count).to eq(2)
      expect(Candidate.find_by!(cnic: '42102-1234567-2')).not_to be_active
    end

    it 'rejects invalid file types' do
      expect do
        described_class.call(
          actor:,
          file: uploaded_csv('not,csv', filename: 'candidates.txt', content_type: 'text/plain'),
          request_id: 'req-import-2'
        )
      end.to raise_error(ValidationError) { |error| expect(error.field).to eq('candidate_import.file') }
    end

    it 'rejects oversized files' do
      stub_const("#{Admin::Candidates::Imports::CsvFileParser}::MAX_FILE_BYTES", 10)

      expect do
        described_class.call(
          actor:,
          file: uploaded_csv(csv_content(['Candidate', '42101-1234567-1', '+923001234567', 'DES-001001', 'en', 'registered',
                                          'registered', 'qatar', 'qatar_infrastructure', 'electrician', 'true'])),
          request_id: 'req-import-3'
        )
      end.to raise_error(ValidationError)
    end

    it 'rejects missing required headers before processing rows' do
      file = uploaded_csv("full_name,cnic\nCandidate,42101-1234567-1\n")

      expect do
        described_class.call(actor:, file:, request_id: 'req-import-4')
      end.to raise_error(ValidationError) { |error| expect(error.message).to include('preferred_locale') }
    end

    it 'rejects malformed csv payloads' do
      file = uploaded_csv(%(full_name,cnic\n"broken,42101-1234567-1))

      expect do
        described_class.call(actor:, file:, request_id: 'req-import-invalid-csv')
      end.to raise_error(ValidationError) { |error| expect(error.field).to eq('candidate_import.file') }
    end

    it 'rejects csv files with no candidate rows' do
      expect do
        described_class.call(actor:, file: uploaded_csv(csv_content), request_id: 'req-import-empty')
      end.to raise_error(ValidationError) { |error| expect(error.message).to include('does not contain') }
    end

    it 'rejects csv files that exceed the configured maximum row count' do
      stub_const("#{Admin::Candidates::Imports::CsvFileParser}::MAX_ROWS", 1)

      expect do
        described_class.call(
          actor:,
          file: uploaded_csv(
            csv_content(
              ['Candidate One', '42101-1234567-1', '+923001234567', 'DES-001001', 'en', 'registered', 'registered', 'qatar',
               'qatar_infrastructure', 'electrician', 'true'],
              ['Candidate Two', '42102-1234567-2', '+923001234568', 'DES-001002', 'ur', 'registered', 'documents_pending', 'uae',
               'qatar_energy', 'welder', 'false']
            )
          ),
          request_id: 'req-import-too-many-rows'
        )
      end.to raise_error(ValidationError) { |error| expect(error.field).to eq('candidate_import.file') }
    end

    it 'reports invalid rows, duplicate rows within the CSV, and existing database duplicates safely' do
      create(:candidate, cnic: '42103-1234567-3')
      create(:candidate_assignment, reference_number: 'DES-009999')

      result = described_class.call(
        actor:,
        file: uploaded_csv(
          csv_content(
            ['Invalid Candidate', 'bad-cnic', 'abc', 'DES-001003', 'en', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true'],
            ['Duplicate In File A', '42104-1234567-4', '+923001234569', 'DES-001004', 'en', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true'],
            ['Duplicate In File B', '42104-1234567-4', '+923001234570', 'DES-001005', 'en', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true'],
            ['Existing Candidate', '42103-1234567-3', '+923001234571', 'DES-001006', 'en', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true'],
            ['Existing Reference', '42105-1234567-5', '+923001234572', 'DES-009999', 'en', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true']
          )
        ),
        request_id: 'req-import-5'
      )

      expect(result[:successful_rows]).to eq(1)
      expect(result[:failed_rows]).to eq(2)
      expect(result[:skipped_rows]).to eq(2)
      expect(result[:errors]).to include(
        include(row: 2, field: 'cnic', code: 'invalid_cnic'),
        include(row: 4, field: 'cnic', code: 'duplicate_cnic_in_file'),
        include(row: 5, field: 'cnic', code: 'duplicate_candidate'),
        include(row: 6, field: 'reference_number', code: 'duplicate_reference_number')
      )
    end

    it 'reports field-level row errors for invalid locale, status, active state, unknown catalogs, and duplicate references in the same file' do
      result = described_class.call(
        actor:,
        file: uploaded_csv(
          csv_content(
            ['Bad Metadata', '42111-1234567-1', '+923001234567', 'DES-001010', 'fr', 'Needs Review', 'missing_stage', 'missing_country',
             'missing_project', 'missing_craft', 'maybe'],
            ['Duplicate Ref A', '42112-1234567-2', '+923001234568', 'DES-001011', 'en', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true'],
            ['Duplicate Ref B', '42113-1234567-3', '+923001234569', 'DES-001011', 'en', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true']
          )
        ),
        request_id: 'req-import-field-errors'
      )

      expect(result[:successful_rows]).to eq(1)
      expect(result[:failed_rows]).to eq(2)
      expect(result[:errors]).to include(
        include(row: 2, field: 'preferred_locale', code: 'invalid_preferred_locale'),
        include(row: 2, field: 'candidate_status', code: 'invalid_candidate_status'),
        include(row: 2, field: 'active', code: 'invalid_active_state'),
        include(row: 2, field: 'workflow_stage_code', code: 'unknown_workflow_stage_code'),
        include(row: 2, field: 'country_code', code: 'unknown_country_code'),
        include(row: 2, field: 'project_code', code: 'unknown_project_code'),
        include(row: 2, field: 'craft_code', code: 'unknown_craft_code'),
        include(row: 4, field: 'reference_number', code: 'duplicate_reference_number_in_file')
      )
    end

    it 'allows a later valid row when an earlier row with the same cnic fails validation' do
      result = described_class.call(
        actor:,
        file: uploaded_csv(
          csv_content(
            ['Broken Candidate', '42121-1234567-1', '+923001234567', 'DES-001020', 'fr', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true'],
            ['Corrected Candidate', '42121-1234567-1', '+923001234568', 'DES-001021', 'en', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true']
          )
        ),
        request_id: 'req-import-invalid-first'
      )

      expect(result).to include(successful_rows: 1, failed_rows: 1, skipped_rows: 0, total_rows: 2)
      expect(result[:errors]).to include(include(row: 2, field: 'preferred_locale', code: 'invalid_preferred_locale'))
      expect(Candidate.find_by!(cnic: '42121-1234567-1').full_name).to eq('Corrected Candidate')
    end

    it 'rejects a later duplicate row after the first valid row reserves the cnic within the same file' do
      result = described_class.call(
        actor:,
        file: uploaded_csv(
          csv_content(
            ['Original Candidate', '42122-1234567-2', '+923001234567', 'DES-001022', 'en', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true'],
            ['Duplicate Candidate', '42122-1234567-2', '+923001234568', 'DES-001023', 'en', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true']
          )
        ),
        request_id: 'req-import-valid-first'
      )

      expect(result).to include(successful_rows: 1, failed_rows: 1, skipped_rows: 0, total_rows: 2)
      expect(result[:errors]).to include(include(row: 3, field: 'cnic', code: 'duplicate_cnic_in_file'))
    end

    it 'records a PII-safe audit event with only summary counts' do
      described_class.call(
        actor:,
        file: uploaded_csv(
          csv_content(
            ['Candidate One', '42101-1234567-1', '+923001234567', 'DES-001001', 'en', 'registered', 'registered', 'qatar',
             'qatar_infrastructure', 'electrician', 'true']
          )
        ),
        request_id: 'req-import-6'
      )

      event = AuditEvent.find_by!(action_code: 'candidate_import_completed', entity_type: 'User', entity_id: actor.id)

      expect(event.metadata).to eq(
        'successful_rows' => 1,
        'failed_rows' => 0,
        'skipped_rows' => 0,
        'total_rows' => 1
      )
      expect(event.metadata.to_s).not_to include('42101-1234567-1')
      expect(event.metadata.to_s).not_to include('+923001234567')
    end

    it 'rolls back imported candidates when the audit event cannot be persisted' do
      allow(AuditEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditEvent.new))

      expect do
        described_class.call(
          actor:,
          file: uploaded_csv(
            csv_content(
              ['Candidate One', '42131-1234567-1', '+923001234567', 'DES-001031', 'en', 'registered', 'registered', 'qatar',
               'qatar_infrastructure', 'electrician', 'true']
            )
          ),
          request_id: 'req-import-audit-failure'
        )
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(Candidate.find_by(cnic: '42131-1234567-1')).to be_nil
      expect(CandidateAssignment.find_by(reference_number: 'DES-001031')).to be_nil
    end
  end
end
