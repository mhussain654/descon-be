# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CandidateBankDetail, type: :model do
  subject(:candidate_bank_detail) { build(:candidate_bank_detail) }

  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:reviewed_by).class_name('User').optional }
  it { is_expected.to validate_inclusion_of(:status_code).in_array(described_class::STATUS_CODES) }

  it 'assigns a public_id on create' do
    candidate_bank_detail.public_id = nil

    candidate_bank_detail.validate

    expect(candidate_bank_detail.public_id).to be_present
  end

  it 'encrypts account title and account number at rest' do
    bank_detail = create(
      :candidate_bank_detail,
      account_title: 'Ahmed Ali',
      account_number: 'PK24 SCBL 0000001123456702'
    )

    raw_title = described_class.connection.select_value(
      "SELECT account_title FROM candidate_bank_details WHERE id = #{bank_detail.id}"
    )
    raw_number = described_class.connection.select_value(
      "SELECT account_number FROM candidate_bank_details WHERE id = #{bank_detail.id}"
    )

    expect(raw_title).not_to eq('Ahmed Ali')
    expect(raw_number).not_to eq('PK24SCBL0000001123456702')
    expect(bank_detail.reload.account_number).to eq('PK24SCBL0000001123456702')
  end

  it 'normalizes account number and preserves attached proof on the current version' do
    bank_detail = create(:candidate_bank_detail, account_number: 'pk24 scbl 0000001123456702')

    expect(bank_detail.reload.account_number).to eq('PK24SCBL0000001123456702')
    expect(bank_detail.proof).to be_attached
  end

  it 'rejects invalid account numbers' do
    candidate_bank_detail.account_number = 'abc-123'

    expect(candidate_bank_detail).not_to be_valid
    expect(candidate_bank_detail.errors[:account_number]).to be_present
  end
end
