# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateImportRowResult do
  subject(:row_result) { described_class.new(candidate_import_batch: batch, row_number: 2, status: 'accepted') }

  let(:batch) do
    CandidateImportBatch.create!(
      actor: create(:user),
      token_digest: SecureRandom.hex(32),
      source_filename: 'candidates.csv',
      file_fingerprint: SecureRandom.hex(32),
      template_version: 'v1',
      preflight_payload: { rows: [] }.to_json,
      expires_at: 30.minutes.from_now
    )
  end

  it { is_expected.to belong_to(:candidate_import_batch) }

  it 'accepts a valid row result' do
    expect(row_result).to be_valid
  end

  it 'rejects unsupported states and non-data row numbers' do
    row_result.status = 'processing'
    row_result.row_number = 1

    expect(row_result).not_to be_valid
    expect(row_result.errors.of_kind?(:status, :inclusion)).to be(true)
    expect(row_result.errors.of_kind?(:row_number, :greater_than)).to be(true)
  end

  it 'allows only one result for each batch row' do
    described_class.create!(candidate_import_batch: batch, row_number: 2, status: 'accepted')

    expect(row_result).not_to be_valid
    expect(row_result.errors.of_kind?(:row_number, :taken)).to be(true)
  end
end
