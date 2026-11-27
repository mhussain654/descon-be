# frozen_string_literal: true

require 'rails_helper'

# Replacing a voucher issued with KuickPay's (unpayable) reference number.
RSpec.describe Payments::ReissueVoucherService do
  before do
    ensure_canonical_workflow_stages!
    create_all_verified_required_documents(assignment:)
  end

  let(:candidate) { create(:candidate, status_code: 'fee_pending', mobile_number: '+923001234567') }
  let(:assignment) do
    create(:candidate_assignment, candidate:, current_workflow_stage: WorkflowStage.find_by!(code: 'fee_pending'),
                                  onboarding_fee_amount: '1500')
  end
  let!(:old_payment) do
    create(:payment, candidate_assignment: assignment, amount: BigDecimal('1500'), provider_code: 'kuickpay_voucher',
                     status_code: 'checkout_pending', voucher_number: '0000826110503906', provider_order_id: 'PAY-OLD',
                     checkout_expires_at: 10.days.from_now)
  end

  def reissue(payment = old_payment, requests: [])
    with_kuickpay_voucher_configured do
      stub_kuickpay_hybrid(requests:)
      described_class.call(payment:, request_id: 'reissue-1')
    end
  end

  it 'cancels the old voucher, issues one with a payable Kuickpay ID and has KuickPay text it' do
    requests = []
    result = reissue(requests:)

    expect(result.old_payment.status_code).to eq('cancelled')
    expect(result.sms_sent).to be(true)
    expect(result.new_payment).to have_attributes(status_code: 'checkout_pending',
                                                  voucher_number: expected_kuickpay_id(result.new_payment))
    sms = requests.find { |request| request.path == '/api/sendSMS' }
    expect(JSON.parse(sms.body)).to include('consumerNo' => result.new_payment.voucher_number)
    expect(PaymentEvent.where(payment: result.new_payment, event_type: 'voucher_sms_sent')).to exist
    expect(AuditEvent.find_by!(action_code: 'candidate_payment_cancelled', entity_id: old_payment.id).metadata)
      .to include('reason' => 'voucher_reissued', 'voucher_number' => '0000826110503906')
  end

  it 'keeps the new voucher and reports it when KuickPay refuses the SMS' do
    with_kuickpay_voucher_configured do
      stub_kuickpay_hybrid
      allow(Payments::Providers::KuickpayVoucherSms).to receive(:new).and_raise(PaymentCheckoutUnavailableError)

      result = described_class.call(payment: old_payment)

      expect(result.sms_sent).to be(false)
      expect(result.new_payment).to be_checkout_pending
      expect(result.old_payment.status_code).to eq('cancelled')
    end
  end

  it 'keeps the old voucher when KuickPay refuses the new one' do
    with_kuickpay_voucher_configured do
      stub_kuickpay_hybrid(insert_code: '05')

      expect { described_class.call(payment: old_payment) }.to raise_error(PaymentCheckoutUnavailableError)
    end
    expect(old_payment.reload).to be_checkout_pending
  end

  it 'refuses a voucher that is already paid, or a card payment' do
    old_payment.update!(status_code: 'paid')
    expect { reissue }.to raise_error(ArgumentError, /only an unpaid voucher/)

    old_payment.update!(status_code: 'checkout_pending', provider_code: 'kuickpay')
    expect { reissue }.to raise_error(ArgumentError, /not a KuickPay voucher/)
  end
end
