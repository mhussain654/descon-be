# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::ExpireVouchersService do
  def voucher(expires_at:, status_code: 'checkout_pending', provider_code: 'kuickpay_voucher')
    create(:payment, candidate_assignment: create(:candidate_assignment), provider_code:, status_code:,
                     provider_order_id: SecureRandom.hex(6), checkout_expires_at: expires_at)
  end

  it 'closes unpaid vouchers a day after they expired, and leaves everything else alone' do
    stale = voucher(expires_at: 2.days.ago)
    in_grace = voucher(expires_at: 6.hours.ago)
    open = voucher(expires_at: 3.days.from_now)
    paid = voucher(expires_at: 2.days.ago, status_code: 'paid')
    card = voucher(expires_at: 2.days.ago, provider_code: 'kuickpay')

    described_class.call

    expect(stale.reload).to have_attributes(status_code: 'cancelled', provider_status_code: 'EXPIRED')
    expect([in_grace, open, paid, card].map { |payment| payment.reload.status_code })
      .to eq(%w[checkout_pending checkout_pending paid checkout_pending])
    expect(AuditEvent.where(action_code: 'candidate_payment_cancelled', entity_id: stale.id)).to exist
  end

  it 'does not touch a voucher that was paid while it was being closed' do
    stale = voucher(expires_at: 2.days.ago)
    allow(stale).to receive(:with_lock).and_yield
    stale.update_columns(status_code: 'paid') # rubocop:disable Rails/SkipsModelValidations
    allow(Payment).to receive(:where).and_call_original

    described_class.call

    expect(stale.reload.status_code).to eq('paid')
  end
end
