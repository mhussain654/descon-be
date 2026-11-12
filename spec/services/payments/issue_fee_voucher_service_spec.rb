# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::IssueFeeVoucherService do
  before { ensure_canonical_workflow_stages! }

  let(:candidate) { create(:candidate, status_code: 'fee_pending', mobile_number: '+923001234567') }
  let(:assignment) do
    create(:candidate_assignment, candidate:, current_workflow_stage: WorkflowStage.find_by!(code: 'fee_pending'),
                                  onboarding_fee_amount: '1500')
  end

  def issue(history_entry_id: 41)
    described_class.call(candidate_assignment_id: assignment.id, history_entry_id:)
  end

  def sms_requests(requests) = requests.select { |request| request.path == '/api/sendSMS' }

  context 'when the candidate can pay by voucher' do
    before { create_all_verified_required_documents(assignment:) }

    it 'issues the code, has KuickPay text it, then queues the fee SMS' do
      requests = []
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid(voucher_number: '0000832249220', requests:)

        expect { issue }.to have_enqueued_job(CandidateSms::DeliveryJob)
      end

      payment = Payment.sole
      expect(payment).to have_attributes(voucher_number: '0000832249220', status_code: 'checkout_pending')
      sms = sms_requests(requests).sole
      expect(sms.uri.host).to eq('api.kuickpay.com')
      expect(JSON.parse(sms.body)).to include('consumerNo' => '0000832249220', 'amount' => '1500',
                                              'cellNumberSMS' => '03001234567')
      expect(PaymentEvent.where(event_type: 'voucher_sms_sent', payment:).count).to eq(1)
      expect(CandidateSmsDelivery.sole).to have_attributes(message_code: 'fee_pending', dedupe_key: 'fee_pending:41')
    end

    it 'texts the code once and sends one fee SMS when run again' do
      requests = []
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid(requests:)

        2.times { issue }
      end

      expect(Payment.count).to eq(1)
      expect(sms_requests(requests).size).to eq(1)
      expect(CandidateSmsDelivery.count).to eq(1)
    end

    it 'texts the code the candidate already asked for, without making a second one' do
      requests = []
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid(requests:)
        Payments::CreateVoucherService.call(candidate:, request_id: 'button')

        issue
      end

      expect(Payment.count).to eq(1)
      expect(sms_requests(requests).size).to eq(1)
    end

    it 'sends no fee SMS when KuickPay refuses to text the code, so the job can retry' do
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid_with_refused_sms

        expect { issue }.to raise_error(PaymentCheckoutUnavailableError)
      end

      expect(CandidateSmsDelivery.count).to eq(0)
      expect(PaymentEvent.where(event_type: 'voucher_sms_sent').count).to eq(0)
    end
  end

  it 'does nothing when vouchers are switched off' do
    create_all_verified_required_documents(assignment:)

    issue

    expect(Payment.count).to eq(0)
    expect(CandidateSmsDelivery.count).to eq(0)
  end

  it 'does nothing for a candidate who can no longer pay (e.g. documents not verified)' do
    with_kuickpay_voucher_configured do
      stub_kuickpay_hybrid

      issue
    end

    expect(Payment.count).to eq(0)
    expect(CandidateSmsDelivery.count).to eq(0)
  end

  it 'does nothing for an inactive candidate or a missing assignment' do
    create_all_verified_required_documents(assignment:)
    candidate.update!(active: false)

    with_kuickpay_voucher_configured do
      issue
      described_class.call(candidate_assignment_id: -1, history_entry_id: 1)
    end

    expect(Payment.count).to eq(0)
  end

  # Insert Voucher succeeds; Send SMS answers with a KuickPay error code.
  def stub_kuickpay_hybrid_with_refused_sms
    allow(Net::HTTP).to receive(:start) do |*, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) { |request| refused_sms_or_voucher(request.path) }
      block.call(http)
    end
  end

  def refused_sms_or_voucher(path)
    return kuickpay_hybrid_response(path, voucher_number: '1', settlements: [], insert_code: '00') \
      unless path == '/api/sendSMS'

    response = Net::HTTPOK.new('1.1', '200', 'OK')
    allow(response).to receive(:body).and_return({ response_Code: '01' }.to_json)
    response
  end
end
