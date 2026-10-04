# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::FeeResolver do
  before { ensure_canonical_workflow_stages! }

  let(:assignment) { create(:candidate_assignment) }

  it 'uses the default unless the assignment has an override' do
    OnboardingFeeSetting.current.update!(amount: '26800')
    expect(described_class.amount(assignment)).to eq(BigDecimal('26800'))
    assignment.update!(onboarding_fee_amount: '25000')
    expect(described_class.amount(assignment)).to eq(BigDecimal('25000'))
  end

  it 'keeps an active bill amount after the default changes' do
    create(:payment, candidate_assignment: assignment, amount: '24000', status_code: 'checkout_pending',
                     checkout_expires_at: 10.minutes.from_now)
    OnboardingFeeSetting.current.update!(amount: '26800')

    expect(described_class.amount(assignment)).to eq(BigDecimal('24000'))
  end

  it 'keeps a settled payment amount' do
    create(:payment, candidate_assignment: assignment, amount: '23000')
    OnboardingFeeSetting.current.update!(amount: '26800')

    expect(described_class.amount(assignment)).to eq(BigDecimal('23000'))
  end

  it 'ignores expired and failed attempts' do
    create(:payment, candidate_assignment: assignment, status_code: 'failed')
    create(:payment, candidate_assignment: assignment, status_code: 'checkout_pending',
                     checkout_expires_at: 1.minute.ago)
    OnboardingFeeSetting.current.update!(amount: '26800')

    expect(described_class.amount(assignment)).to eq(BigDecimal('26800'))
  end

  it 'does not carry an override to a later assignment' do
    assignment.update!(onboarding_fee_amount: '23000')
    later = create(:candidate_assignment, candidate: assignment.candidate)
    OnboardingFeeSetting.current.update!(amount: '26800')

    expect(described_class.amount(later)).to eq(BigDecimal('26800'))
  end
end
