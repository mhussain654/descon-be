# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::Documents::UploadService do
  def existing_or_create_document_type(code, name_en:, name_ur:)
    DocumentType.find_or_create_by!(code:) do |document_type|
      document_type.name_en = name_en
      document_type.name_ur = name_ur
      document_type.active = true
      document_type.requires_number = false
      document_type.requires_expiry = false
    end
  end

  let(:candidate) { create(:candidate) }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:document_type) { existing_or_create_document_type('passport', name_en: 'Passport', name_ur: 'پاسپورٹ') }
  let(:pcc_code) { CandidateDocument::PCC_REQUIREMENT_CODE }
  let(:pcc_type) do
    existing_or_create_document_type(
      pcc_code,
      name_en: 'Police Character Certificate',
      name_ur: 'پولیس کریکٹر سرٹیفکیٹ'
    )
  end

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
      expect(assignment.reload.current_workflow_stage.code).to eq('documents_uploaded')
      expect(candidate.reload.status_code).to eq('documents_uploaded')
      expect(CandidateDocument.current_version.where(candidate_assignment: assignment, document_type:).count).to eq(1)
      expect(AuditEvent.where(action_code: 'candidate_document_uploaded').count).to eq(1)
      expect(AuditEvent.where(action_code: 'candidate_workflow_transitioned').count).to eq(2)
      expect(assignment.candidate_stage_histories.where(reason_code: 'auto_documents_uploaded').count).to eq(2)
    end

    it 'captures issue date and calculates PCC expiry exactly six calendar months later' do
      create(
        :document_requirement,
        document_type: pcc_type,
        country: assignment.country,
        project: assignment.project,
        craft: assignment.craft
      )

      result = described_class.call(
        candidate:,
        uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
        requirement_code: pcc_code,
        pcc_attributes: { issued_on: '2026-08-28' },
        request_id: 'req-doc-upload-pcc-1'
      )

      document = CandidateDocument.current_version.find_by!(
        candidate_assignment: assignment,
        document_type: pcc_type
      )

      expect(document.issued_on).to eq(Date.new(2026, 8, 28))
      expect(document.expires_on).to eq(Date.new(2027, 2, 28))
      expect(result.document[:issued_on]).to eq('2026-08-28')
      expect(result.document[:expires_on]).to eq('2027-02-28')
      expect(result.document[:compliance_status]).to eq('current')

      event = AuditEvent.where(action_code: 'candidate_document_uploaded').order(:id).last
      expect(event.metadata).to include(
        'candidate_public_id' => candidate.public_id,
        'document_public_id' => document.public_id,
        'requirement_code' => pcc_code,
        'issued_on' => '2026-08-28',
        'expires_on' => '2027-02-28'
      )
      expect(event.metadata.to_json).not_to include(document.checksum_sha256.to_s)
    end

    it 'recalculates PCC expiry on replacement and preserves the previous version dates' do
      create(
        :document_requirement,
        document_type: pcc_type,
        country: assignment.country,
        project: assignment.project,
        craft: assignment.craft
      )
      existing_document = create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: pcc_type,
        issued_on: Date.new(2026, 1, 1)
      )

      described_class.call(
        candidate:,
        uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
        requirement_code: pcc_code,
        pcc_attributes: { issued_on: '2026-08-15' },
        request_id: 'req-doc-upload-pcc-2'
      )

      replacement = CandidateDocument.current_version.find_by!(
        candidate_assignment: assignment,
        document_type: pcc_type
      )

      expect(existing_document.reload.superseded_at).to be_present
      expect(existing_document.issued_on).to eq(Date.new(2026, 1, 1))
      expect(existing_document.expires_on).to eq(Date.new(2026, 7, 1))
      expect(replacement.issued_on).to eq(Date.new(2026, 8, 15))
      expect(replacement.expires_on).to eq(Date.new(2027, 2, 15))
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
      expect(AuditEvent.where(action_code: 'candidate_document_replaced').count).to eq(1)
      expect(AuditEvent.where(action_code: 'candidate_workflow_transitioned').count).to eq(2)
      expect(assignment.candidate_stage_histories.where(reason_code: 'auto_documents_uploaded').count).to eq(2)
    end

    it 'advances to documents_uploaded only after every mandatory requirement has a compliant upload' do
      cv_type = existing_or_create_document_type('cv', name_en: 'CV', name_ur: 'سی وی')
      create(
        :document_requirement,
        document_type: cv_type,
        country: assignment.country,
        project: assignment.project,
        craft: assignment.craft
      )

      described_class.call(
        candidate:,
        uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
        requirement_code: 'passport',
        request_id: 'req-doc-upload-stage-1'
      )

      expect(assignment.reload.current_workflow_stage.code).to eq('documents_pending')

      described_class.call(
        candidate:,
        uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
        requirement_code: 'cv',
        request_id: 'req-doc-upload-stage-2'
      )

      expect(assignment.reload.current_workflow_stage.code).to eq('documents_uploaded')
      expect(candidate.reload.status_code).to eq('documents_uploaded')
    end

    it 'allows expired verified pcc replacement without rewriting workflow history' do
      create(
        :document_requirement,
        document_type: pcc_type,
        country: assignment.country,
        project: assignment.project,
        craft: assignment.craft
      )
      assignment.update!(current_workflow_stage: WorkflowStage.find_by!(code: 'verified'))
      candidate.update!(status_code: 'verified')
      current_document = create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: pcc_type,
        status_code: 'verified',
        issued_on: Date.new(2026, 1, 1),
        verified_by: create(:user),
        verified_at: Time.zone.parse('2026-08-01T09:00:00Z')
      )

      expect(current_document.compliance_status).to eq('expired')

      described_class.call(
        candidate:,
        uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
        requirement_code: pcc_code,
        pcc_attributes: { issued_on: '2026-08-28' },
        request_id: 'req-doc-upload-pcc-replacement-1'
      )

      replacement = CandidateDocument.current_version.find_by!(
        candidate_assignment: assignment,
        document_type: pcc_type
      )

      expect(current_document.reload.superseded_at).to be_present
      expect(replacement.status_code).to eq('uploaded')
      expect(assignment.reload.current_workflow_stage.code).to eq('verified')
      expect(candidate.reload.status_code).to eq('verified')
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

    it 'rolls back a first-time upload when workflow transition persistence fails and purges the orphan blob' do
      original_blob_ids = ActiveStorage::Blob.pluck(:id)

      allow(CandidateWorkflows::TransitionRecorder).to receive(:call)
        .and_raise(ActiveRecord::RecordInvalid.new(CandidateStageHistory.new))

      expect do
        described_class.call(
          candidate:,
          uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
          requirement_code: 'passport',
          request_id: 'req-doc-upload-rollback-1'
        )
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(CandidateDocument.current_version.where(candidate_assignment: assignment, document_type:).count).to eq(0)
      expect(AuditEvent.where(action_code: 'candidate_document_uploaded')).to be_empty
      expect(AuditEvent.where(action_code: 'candidate_workflow_transitioned')).to be_empty
      expect(assignment.reload.candidate_stage_histories).to be_empty
      expect(assignment.current_workflow_stage.code).to eq('registered')
      expect(candidate.reload.status_code).to eq('registered')
      expect(ActiveStorage::Blob.pluck(:id)).to match_array(original_blob_ids)
    end

    it 'rolls back a replacement upload when workflow transition persistence fails and keeps the previous ' \
       'current document' do
      existing_document = create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type:,
        status_code: 'uploaded'
      )
      original_blob_ids = ActiveStorage::Blob.pluck(:id)

      allow(CandidateWorkflows::TransitionRecorder).to receive(:call)
        .and_raise(ActiveRecord::RecordInvalid.new(CandidateStageHistory.new))

      expect do
        described_class.call(
          candidate:,
          uploaded_file: fixture_upload('test.jpg', 'image/jpeg'),
          requirement_code: 'passport',
          request_id: 'req-doc-upload-rollback-2'
        )
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(existing_document.reload.superseded_at).to be_nil
      expect(CandidateDocument.current_version.where(candidate_assignment: assignment, document_type:).pluck(:id))
        .to eq([existing_document.id])
      expect(AuditEvent.where(action_code: 'candidate_document_replaced')).to be_empty
      expect(AuditEvent.where(action_code: 'candidate_workflow_transitioned')).to be_empty
      expect(assignment.reload.candidate_stage_histories).to be_empty
      expect(assignment.current_workflow_stage.code).to eq('registered')
      expect(candidate.reload.status_code).to eq('registered')
      expect(ActiveStorage::Blob.pluck(:id)).to match_array(original_blob_ids)
    end

    it 'preserves the previous PCC document and its dates when replacement fails' do
      create(
        :document_requirement,
        document_type: pcc_type,
        country: assignment.country,
        project: assignment.project,
        craft: assignment.craft
      )
      existing_document = create(
        :candidate_document,
        candidate_assignment: assignment,
        document_type: pcc_type,
        issued_on: Date.new(2026, 1, 1)
      )

      allow(AuditEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditEvent.new))

      expect do
        described_class.call(
          candidate:,
          uploaded_file: fixture_upload('test.jpg', 'image/jpeg'),
          requirement_code: pcc_code,
          pcc_attributes: { issued_on: '2026-08-01' },
          request_id: 'req-doc-upload-pcc-3'
        )
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(existing_document.reload.superseded_at).to be_nil
      expect(existing_document.issued_on).to eq(Date.new(2026, 1, 1))
      expect(existing_document.expires_on).to eq(Date.new(2026, 7, 1))
      expect(
        CandidateDocument.current_version.where(candidate_assignment: assignment, document_type: pcc_type).count
      ).to eq(1)
    end

    it 'requires a valid non-future issue date for PCC uploads and rejects client-supplied expiry' do
      create(
        :document_requirement,
        document_type: pcc_type,
        country: assignment.country,
        project: assignment.project,
        craft: assignment.craft
      )

      expect do
        described_class.call(
          candidate:,
          uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
          requirement_code: pcc_code,
          request_id: 'req-doc-upload-pcc-4'
        )
      end.to raise_error(ValidationError, I18n.t('api.errors.pcc_issue_date_required'))

      expect do
        described_class.call(
          candidate:,
          uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
          requirement_code: pcc_code,
          pcc_attributes: { issued_on: '2026-02-30' },
          request_id: 'req-doc-upload-pcc-5'
        )
      end.to raise_error(ValidationError, I18n.t('api.errors.pcc_issue_date_invalid'))

      expect do
        described_class.call(
          candidate:,
          uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
          requirement_code: pcc_code,
          pcc_attributes: { issued_on: '2026-09-01' },
          request_id: 'req-doc-upload-pcc-6'
        )
      end.to raise_error(ValidationError, I18n.t('api.errors.pcc_issue_date_in_future'))

      expect do
        described_class.call(
          candidate:,
          uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
          requirement_code: pcc_code,
          pcc_attributes: {
            issued_on: '2026-08-01',
            expires_on: '2027-02-01'
          },
          request_id: 'req-doc-upload-pcc-7'
        )
      end.to raise_error(PccExpiryNotEditableError)
    end

    it 'does not persist PCC date fields for non-PCC uploads even when issued_on is sent' do
      described_class.call(
        candidate:,
        uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
        requirement_code: 'passport',
        pcc_attributes: { issued_on: '2026-08-01' },
        request_id: 'req-doc-upload-6'
      )

      document = CandidateDocument.current_version.find_by!(candidate_assignment: assignment, document_type:)

      expect(document.issued_on).to be_nil
      expect(document.expires_on).to be_nil
    end

    it 'purges an unattached blob and re-raises unexpected failures' do
      original_blob_ids = ActiveStorage::Blob.pluck(:id)

      allow(Candidates::Documents::UploadPersistence).to receive(:call).and_raise(RuntimeError, 'unexpected failure')

      expect do
        described_class.call(
          candidate:,
          uploaded_file: fixture_upload('test.pdf', 'application/pdf'),
          requirement_code: 'passport',
          request_id: 'req-doc-upload-5'
        )
      end.to raise_error(RuntimeError, 'unexpected failure')

      expect(ActiveStorage::Blob.pluck(:id)).to match_array(original_blob_ids)
      expect(CandidateDocument.count).to eq(0)
    end
  end
end
