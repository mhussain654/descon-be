# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payment, type: :model do
  subject(:payment) { build(:payment) }

  it { is_expected.to belong_to(:candidate_assignment) }
  it { is_expected.to belong_to(:recorded_by).class_name('User').optional }

  it 'normalizes payment codes and currency' do
    payment.payment_type_code = ' ONBOARDING_FEE '
    payment.status_code = ' PAID '
    payment.currency_code = ' pkr '
    payment.validate

    expect(payment.payment_type_code).to eq('onboarding_fee')
    expect(payment.status_code).to eq('paid')
    expect(payment.currency_code).to eq('PKR')
  end

  it 'validates external reference uniqueness when present' do
    existing_payment = create(:payment, external_reference: 'PAY-001')
    duplicate_payment = build(:payment, external_reference: existing_payment.external_reference)

    expect(duplicate_payment).not_to be_valid
    expect(duplicate_payment.errors[:external_reference]).to include('has already been taken')
  end

  it 'requires a positive amount' do
    payment.amount = 0

    expect(payment).not_to be_valid
  end
end
