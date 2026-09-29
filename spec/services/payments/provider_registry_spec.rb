# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::ProviderRegistry do
  it 'returns a kuickpay adapter for the kuickpay provider code' do
    provider = described_class.fetch('kuickpay')

    expect(provider).to be_a(Payments::Providers::KuickpayHostedCheckoutAdapter)
  end

  it 'defaults to kuickpay when no provider code is given' do
    provider = described_class.fetch

    expect(provider).to be_a(Payments::Providers::KuickpayHostedCheckoutAdapter)
  end

  it 'rejects unknown provider codes' do
    expect do
      described_class.fetch('unknown_provider')
    end.to raise_error(Payments::ProviderNotConfiguredError, /Unknown payment provider/)
  end
end
