# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::Providers::MockHostedCheckoutAdapter do
  let(:configuration) do
    instance_double(
      Payments::Configuration,
      checkout_expires_in_minutes: 30,
      mock_base_url: 'https://app.example.test/mock_checkout',
      mock_secret: 'mock-secret-1'
    )
  end

  let(:adapter) { described_class.new(configuration:) }
  let(:payment) do
    build_stubbed(:payment, provider_order_id: 'PAY-ORDER-123', amount: BigDecimal('1500.00'), currency_code: 'PKR')
  end

  describe '#simulated_return_params' do
    %w[success failed cancelled].each do |outcome|
      it "round-trips through #parse_notification! for a #{outcome} outcome" do
        params = adapter.simulated_return_params(payment:, outcome:)

        notification = adapter.parse_notification!(event_source: 'return', params:)

        expect(notification.provider_order_id).to eq('PAY-ORDER-123')
        expect(notification.amount).to eq(BigDecimal('1500.00'))
        expect(notification.currency_code).to eq('PKR')
      end
    end

    it 'marks a success outcome as successful and a failed outcome as not' do
      success_notification = adapter.parse_notification!(
        event_source: 'return', params: adapter.simulated_return_params(payment:, outcome: 'success')
      )
      failed_notification = adapter.parse_notification!(
        event_source: 'return', params: adapter.simulated_return_params(payment:, outcome: 'failed')
      )

      expect(success_notification).to be_success
      expect(failed_notification).not_to be_success
      expect(failed_notification).to be_failed
    end

    it 'raises for an unknown outcome' do
      expect { adapter.simulated_return_params(payment:, outcome: 'bogus') }.to raise_error(KeyError)
    end
  end
end
