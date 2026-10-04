# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OnboardingFeeSetting do
  it 'retains the configured initial fee and then uses the database default' do
    original = ENV.fetch('ONBOARDING_FEE_AMOUNT', nil)
    ENV['ONBOARDING_FEE_AMOUNT'] = '26800'
    record = described_class.current
    record.update!(amount: '25000')
    ENV['ONBOARDING_FEE_AMOUNT'] = '29000'

    expect(described_class.current.amount).to eq(BigDecimal('25000'))
    expect(described_class.count).to eq(1)
  ensure
    original.nil? ? ENV.delete('ONBOARDING_FEE_AMOUNT') : ENV['ONBOARDING_FEE_AMOUNT'] = original
  end

  it 'rejects zero and negative defaults' do
    expect(described_class.new(amount: 0)).not_to be_valid
    expect(described_class.new(amount: -1)).not_to be_valid
  end
end
