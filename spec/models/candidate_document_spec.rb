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
    candidate_document.verified_by = create(:user)
    candidate_document.verified_at = nil
    candidate_document.valid?

    expect(candidate_document.errors[:verified_at]).to include("can't be blank")
  end
end
