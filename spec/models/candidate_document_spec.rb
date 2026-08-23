# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateDocument, type: :model do
  subject(:candidate_document) { build(:candidate_document) }

  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:document_type) }
  it { is_expected.to belong_to(:uploaded_by).class_name('User').optional }
  it { is_expected.to belong_to(:verified_by).class_name('User').optional }

  it 'normalizes the status code and checksum' do
    candidate_document.status_code = ' VERIFIED '
    candidate_document.checksum_sha256 = ' ABCDEF '
    candidate_document.validate

    expect(candidate_document.status_code).to eq('verified')
    expect(candidate_document.checksum_sha256).to eq('abcdef')
  end

  it 'requires verification user and time together' do
    candidate_document.status_code = 'verified'
    candidate_document.verified_by = create(:user)
    candidate_document.verified_at = nil
    candidate_document.valid?

    expect(candidate_document.errors[:verified_at]).to include("can't be blank")
  end

  it 'rejects verified documents without verification metadata' do
    candidate_document.status_code = 'verified'
    candidate_document.verified_by = nil
    candidate_document.verified_at = nil

    expect(candidate_document).not_to be_valid
    expect(candidate_document.errors[:verified_by]).to include("can't be blank")
    expect(candidate_document.errors[:verified_at]).to include("can't be blank")
  end

  it 'rejects uploaded documents with verification metadata' do
    candidate_document.status_code = 'uploaded'
    candidate_document.verified_by = create(:user)
    candidate_document.verified_at = Time.current

    expect(candidate_document).not_to be_valid
    expect(candidate_document.errors[:verified_by]).to include('must be blank')
    expect(candidate_document.errors[:verified_at]).to include('must be blank')
  end

  it 'requires a rejection reason for rejected documents' do
    candidate_document.status_code = 'rejected'
    candidate_document.verified_by = create(:user)
    candidate_document.verified_at = Time.current
    candidate_document.rejection_reason = nil

    expect(candidate_document).not_to be_valid
    expect(candidate_document.errors[:rejection_reason]).to include("can't be blank")
  end

  it 'rejects non-rejected documents with a rejection reason' do
    candidate_document.status_code = 'verified'
    candidate_document.verified_by = create(:user)
    candidate_document.verified_at = Time.current
    candidate_document.rejection_reason = 'Mismatch'

    expect(candidate_document).not_to be_valid
    expect(candidate_document.errors[:rejection_reason]).to include('must be blank')
  end

  it 'enforces status consistency at the database level' do
    document = create(:candidate_document)

    expect do
      described_class.connection.exec_update(
        <<~SQL.squish,
          UPDATE candidate_documents
          SET status_code = 'verified',
              verified_by_id = NULL,
              verified_at = NULL,
              rejection_reason = NULL
          WHERE id = #{document.id}
        SQL
        'SQL'
      )
    end.to raise_error(ActiveRecord::StatementInvalid)
  end
end
