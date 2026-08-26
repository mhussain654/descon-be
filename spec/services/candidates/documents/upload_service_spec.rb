# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::Documents::UploadService do
  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:document_type) { create(:document_type, code: 'passport', name_en: 'Passport', name_ur: 'پاسپورٹ') }

  before do
    create(
      :document_requirement,
      document_type:,
      country: assignment.country,
      project: assignment.project,
      craft: assignment.craft
    )
  end

  describe '.call' do
    it 'uploads a candidate document and returns a checklist item' do
      result = described_class.call(
        candidate:,
        uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
        requirement_code: 'passport',
        request_id: 'req-doc-upload-1'
      )

      document = CandidateDocument.current_version.find_by!(candidate_assignment: assignment, document_type:)

      expect(result.requirement_code).to eq('passport')
      expect(result.status).to eq('uploaded')
      expect(result.document[:id]).to eq(document.public_id)
      expect(document.file).to be_attached
    end

    it 'replaces an uploaded document and supersedes the previous current version' do
      existing_document = create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type:,
        status_code: 'uploaded'
      )

      result = described_class.call(
        candidate:,
        uploaded_file: fixture_upload('test.png', 'image/png'),
        requirement_code: 'passport',
        request_id: 'req-doc-upload-2'
      )

      expect(result.status).to eq('uploaded')
      expect(existing_document.reload.superseded_at).to be_present
      expect(CandidateDocument.current_version.where(candidate_assignment: assignment, document_type:).count).to eq(1)
    end

    it 'rejects replacement when the current document status is not replaceable' do
      create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type:,
        status_code: 'verified',
        verified_by: create(:user),
        verified_at: Time.current
      )

      expect do
        described_class.call(
          candidate:,
          uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
          requirement_code: 'passport',
          request_id: 'req-doc-upload-3'
        )
      end.to raise_error(ReplacementNotAllowedError)
    end

    it 'preserves the previous current document and purges the new blob on audit failure during replacement' do
      existing_document = create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type:,
        status_code: 'uploaded'
      )
      original_blob_ids = ActiveStorage::Blob.pluck(:id)

      allow(AuditEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditEvent.new))

      expect do
        described_class.call(
          candidate:,
          uploaded_file: fixture_upload('test.jpg', 'image/jpeg'),
          requirement_code: 'passport',
          request_id: 'req-doc-upload-4'
        )
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(existing_document.reload.superseded_at).to be_nil
      expect(CandidateDocument.current_version.where(candidate_assignment: assignment, document_type:).count).to eq(1)
      expect(ActiveStorage::Blob.pluck(:id)).to match_array(original_blob_ids)
    end
  end
end
