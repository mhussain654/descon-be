# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateDocument, type: :model do
  subject(:candidate_document) { build(:candidate_document) }

  def police_character_type
    DocumentType.find_or_create_by!(code: CandidateDocument::PCC_REQUIREMENT_CODE) do |document_type|
      document_type.name_en = 'Police Character Certificate'
      document_type.name_ur = 'پولیس کریکٹر سرٹیفکیٹ'
      document_type.active = true
      document_type.requires_number = false
      document_type.requires_expiry = false
    end
  end

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

  it 'calculates PCC expiry exactly six calendar months after the issue date' do
    candidate_document.document_type = police_character_type
    candidate_document.issued_on = Date.new(2026, 8, 1)

    expect(candidate_document).to be_valid
    expect(candidate_document.expires_on).to eq(Date.new(2027, 2, 1))
  end

  it 'handles end-of-month and leap-year PCC expiry with calendar-month arithmetic' do
    candidate_document.document_type = police_character_type
    candidate_document.issued_on = Date.new(2024, 8, 31)
    candidate_document.validate
    expect(candidate_document.expires_on).to eq(Date.new(2025, 2, 28))

    candidate_document.issued_on = Date.new(2023, 8, 31)
    candidate_document.validate
    expect(candidate_document.expires_on).to eq(Date.new(2024, 2, 29))
  end

  it 'rejects a future PCC issue date at the model layer' do
    travel_to(Time.zone.local(2026, 8, 28, 12, 0, 0)) do
      candidate_document.document_type = police_character_type
      candidate_document.issued_on = Date.new(2026, 8, 29)

      expect(candidate_document).not_to be_valid
      expect(candidate_document.errors[:issued_on]).to include('is invalid')
    end
  end

  it 'clears issue and expiry dates for non-PCC documents before persistence' do
    candidate_document.document_type = create(:document_type, code: "passport_#{SecureRandom.hex(4)}")
    candidate_document.issued_on = Date.new(2026, 8, 1)
    candidate_document.expires_on = Date.new(2027, 2, 1)

    expect(candidate_document).to be_valid
    expect(candidate_document.issued_on).to be_nil
    expect(candidate_document.expires_on).to be_nil
  end

  it 'exposes current, near-expiry, and expired compliance states for PCC documents' do
    freeze_time do
      travel_to(Time.zone.local(2026, 8, 28, 12, 0, 0))
      candidate_document.document_type = police_character_type

      candidate_document.issued_on = Date.new(2026, 8, 1)
      candidate_document.validate
      expect(candidate_document.compliance_status).to eq('current')

      candidate_document.expires_on = Date.new(2026, 9, 10)
      expect(candidate_document.compliance_status).to eq('near_expiry')

      candidate_document.expires_on = Date.new(2026, 8, 27)
      expect(candidate_document.compliance_status).to eq('expired')
    end
  end

  it 'supports SQL-backed PCC compliance scopes and expiry ranges' do
    freeze_time do
      travel_to(Time.zone.local(2026, 8, 28, 12, 0, 0))
      pcc_type = police_character_type
      current_document = create(:candidate_document, document_type: pcc_type, issued_on: Date.new(2026, 8, 1))
      near_expiry_document = create(:candidate_document, document_type: pcc_type, issued_on: Date.new(2026, 3, 10))
      expired_document = create(:candidate_document, document_type: pcc_type, issued_on: Date.new(2026, 2, 1))

      expect(described_class.current_pcc).to include(current_document)
      expect(described_class.current_pcc).not_to include(near_expiry_document, expired_document)

      expect(described_class.near_expiry_pcc).to include(near_expiry_document)
      expect(described_class.near_expiry_pcc).not_to include(current_document, expired_document)

      expect(described_class.expired_pcc).to include(expired_document)
      expect(described_class.expired_pcc).not_to include(current_document, near_expiry_document)

      expect(described_class.pcc_expiring_between(Date.new(2026, 9, 1), Date.new(2026, 9, 30)))
        .to include(near_expiry_document)
    end
  end

  it 'raises on invalid PCC warning-window configuration' do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('PCC_NEAR_EXPIRY_DAYS', 30).and_return('-1')

    expect { described_class.pcc_near_expiry_days }.to raise_error(ArgumentError, /PCC_NEAR_EXPIRY_DAYS/)
  end
end
