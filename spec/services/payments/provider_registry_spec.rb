# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::ProviderRegistry do
  it 'returns a kuickpay adapter for the kuickpay provider code' do
    provider = described_class.fetch('kuickpay')

    expect(provider).to be_a(Payments::Providers::KuickpayHostedCheckoutAdapter)
  end

  it 'rejects the mock hosted checkout provider in production' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

    expect do
      described_class.fetch('mock_hosted_checkout')
    end.to raise_error(Payments::ProviderNotConfiguredError)
  end

  it 'rejects the mock hosted checkout provider in staging' do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('staging'))

    expect do
      described_class.fetch('mock_hosted_checkout')
    end.to raise_error(Payments::ProviderNotConfiguredError)
  end

  it 'rejects unknown provider codes' do
    expect do
      described_class.fetch('unknown_provider')
    end.to raise_error(Payments::ProviderNotConfiguredError, /Unknown PAYMENT_PROVIDER/)
  end
end
