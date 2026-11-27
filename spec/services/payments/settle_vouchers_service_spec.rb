# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::SettleVouchersService do
  before do
    ensure_canonical_workflow_stages!
    create_all_verified_required_documents(assignment:)
  end

  let(:candidate) { create(:candidate, status_code: 'fee_pending') }
  let(:assignment) do
    create(:candidate_assignment, candidate:, current_workflow_stage: WorkflowStage.find_by!(code: 'fee_pending'),
                                  onboarding_fee_amount: '1500')
  end
  let!(:payment) do
    create(:payment, candidate_assignment: assignment, amount: BigDecimal('1500'), provider_code: 'kuickpay_voucher',
                     status_code: 'checkout_pending', voucher_number: '0000811111', provider_order_id: 'PAY-1',
                     checkout_expires_at: 5.days.from_now)
  end

  def run_with(settlements, requests: [])
    with_kuickpay_voucher_configured do
      stub_kuickpay_hybrid(settlements:, requests:)
      described_class.call
    end
  end

  it 'finds the voucher by its registration number when KuickPay lists it under another number' do
    payment.update!(voucher_number: '0000800000042')
    row = kuickpay_settlement(consumer_number: '0000820261109065315', amount: 1500, registration_number: '00000042')

    expect(run_with([row])).to eq(1)
    expect(payment.reload).to be_paid
  end

  it "pays the candidate's unpaid voucher when an expired one shares its Kuickpay ID" do
    payment.update!(checkout_expires_at: 2.days.ago, created_at: 3.days.ago)
    newer = create(:payment, candidate_assignment: assignment, amount: BigDecimal('1500'),
                             provider_code: 'kuickpay_voucher', status_code: 'checkout_pending',
                             voucher_number: '0000811111', provider_order_id: 'PAY-NEW',
                             checkout_expires_at: 5.days.from_now)
    payment.update!(status_code: 'cancelled')

    expect(run_with([kuickpay_settlement(consumer_number: '0000811111', amount: 1500)])).to eq(1)
    expect(newer.reload).to be_paid
    expect(payment.reload.status_code).to eq('cancelled')
  end

  it 'never pays a later voucher with a payment already recorded against an earlier one' do
    run_with([kuickpay_settlement(consumer_number: '0000811111', amount: 1500, auth_id: '788895')])
    newer = create(:payment, candidate_assignment: assignment, amount: BigDecimal('1500'),
                             provider_code: 'kuickpay_voucher', status_code: 'checkout_pending',
                             voucher_number: '0000811111', provider_order_id: 'PAY-NEW',
                             checkout_expires_at: 5.days.from_now)

    expect(run_with([kuickpay_settlement(consumer_number: '0000811111', amount: 1500, auth_id: '788895')])).to eq(0)
    expect(newer.reload).to be_checkout_pending
  end

  it 'leaves a payment alone when neither the number nor the registration number matches' do
    row = kuickpay_settlement(consumer_number: '0000899999', amount: 1500, registration_number: 'DES500002')

    expect(run_with([row])).to eq(0)
    expect(payment.reload).to be_checkout_pending
  end

  it 'marks a paid voucher paid and moves the candidate to Fee Paid' do
    count = run_with([kuickpay_settlement(consumer_number: '0000811111', amount: 1500, auth_id: '788895')])

    expect(count).to eq(1)
    expect(payment.reload).to have_attributes(status_code: 'paid', external_reference: '788895',
                                              provider_transaction_id: '788895')
    expect(payment.paid_at).to be_present
    expect(assignment.reload.current_workflow_stage.code).to eq('fee_paid')
    expect(PaymentEvent.where(event_type: 'payment_succeeded', provider_code: 'kuickpay_voucher').count).to eq(1)
    expect(AuditEvent.where(action_code: 'candidate_payment_paid').count).to eq(1)
  end

  it 'marks a voucher paid as soon as KuickPay lists it, before KuickPay settles it', :aggregate_failures do
    row = kuickpay_settlement(consumer_number: '0000811111', amount: 1500, settled: false)

    expect(run_with([row])).to eq(1)

    expect(payment.reload.status_code).to eq('paid')
    expect(payment.paid_at).to eq(Time.find_zone('UTC').parse('2026-10-21 09:16:02'))
    expect(assignment.reload.current_workflow_stage.code).to eq('fee_paid')
  end

  it 'does nothing the second time it sees the same payment, even once KuickPay has settled it' do
    run_with([kuickpay_settlement(consumer_number: '0000811111', amount: 1500, settled: false)])
    row = kuickpay_settlement(consumer_number: '0000811111', amount: 1500)
    payment.update!(status_code: 'checkout_pending', paid_at: nil)

    expect(run_with([row])).to eq(0)
    expect(PaymentEvent.where(event_type: 'payment_succeeded').count).to eq(1)
  end

  it 'leaves a voucher unpaid when the amount does not match, and still handles the others' do
    other = create(:payment, candidate_assignment: create(:candidate_assignment), amount: BigDecimal('1500'),
                             provider_code: 'kuickpay_voucher', status_code: 'checkout_pending',
                             voucher_number: '0000822222', provider_order_id: 'PAY-2',
                             checkout_expires_at: 5.days.from_now)

    count = run_with([kuickpay_settlement(consumer_number: '0000811111', amount: 1400),
                      kuickpay_settlement(consumer_number: '0000822222', amount: 1500, auth_id: '111111')])

    expect(count).to eq(1)
    expect(payment.reload.status_code).to eq('checkout_pending')
    expect(other.reload.status_code).to eq('paid')
  end

  it 'ignores a settlement for a voucher it does not know' do
    expect(run_with([kuickpay_settlement(consumer_number: '0000899999', amount: 1500)])).to eq(0)
    expect(payment.reload.status_code).to eq('checkout_pending')
  end

  it 'makes one call, for today in Pakistan time, and only when a voucher is waiting' do
    requests = []
    run_with([], requests:)

    dates = requests.map { |request| JSON.parse(request.body)['transactionDate'] }
    expect(dates).to eq([Time.current.in_time_zone('Asia/Karachi').to_date.strftime('%Y%m%d')])

    payment.update!(status_code: 'cancelled')
    requests.clear
    run_with([], requests:)
    expect(requests).to be_empty
  end

  it 'asks about yesterday instead when told to (the 10:00 run)' do
    requests = []
    with_kuickpay_voucher_configured do
      stub_kuickpay_hybrid(settlements: [], requests:)
      described_class.call(days_ago: 1)
    end

    yesterday = Time.current.in_time_zone('Asia/Karachi').to_date - 1
    expect(requests.map { |request| JSON.parse(request.body)['transactionDate'] }).to eq([yesterday.strftime('%Y%m%d')])
  end

  it 'refuses any day other than today or yesterday' do
    expect { described_class.new(days_ago: 2) }.to raise_error(ArgumentError)
  end

  it 'does nothing when voucher payments are switched off' do
    expect(described_class.call).to eq(0)
  end
end
