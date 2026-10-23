# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::PollVoucherSettlementsJob do
  it 'notices paid vouchers and then closes expired ones' do
    allow(Payments::SettleVouchersService).to receive(:call)
    allow(Payments::ExpireVouchersService).to receive(:call)

    described_class.perform_now

    expect(Payments::SettleVouchersService).to have_received(:call).ordered
    expect(Payments::ExpireVouchersService).to have_received(:call).ordered
  end

  it 'skips the run, without failing, when KuickPay is unavailable' do
    allow(Payments::SettleVouchersService).to receive(:call).and_raise(PaymentCheckoutUnavailableError)
    allow(Payments::ExpireVouchersService).to receive(:call)

    expect { described_class.perform_now }.not_to raise_error
    expect(Payments::ExpireVouchersService).not_to have_received(:call)
  end
end
