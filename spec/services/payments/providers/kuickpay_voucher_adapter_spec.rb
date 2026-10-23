# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Payments::Providers::KuickpayVoucherAdapter do
  let(:configuration) { Payments::Configuration.new }
  let(:adapter) { described_class.new(configuration:) }
  let(:candidate) { create(:candidate, full_name: 'Ayesha Khan 2', mobile_number: '+923001234567') }
  let(:assignment) { create(:candidate_assignment, candidate:) }
  let(:payment) do
    create(:payment, candidate_assignment: assignment, amount: BigDecimal('1500'), provider_code: 'kuickpay_voucher',
                     provider_order_id: 'PAY-REF-1')
  end

  describe '#available?' do
    it 'needs the voucher switch on' do
      expect(adapter).not_to be_available

      with_kuickpay_voucher_configured { expect(adapter).to be_available }
    end

    it 'needs the hybrid login and an institution id' do
      with_kuickpay_voucher_configured do
        allow(configuration).to receive(:kuickpay_hybrid_username).and_return('')
        expect(adapter).not_to be_available
      end
      with_kuickpay_voucher_configured do
        allow(configuration).to receive(:kuickpay_institution_id).and_return(nil)
        expect(adapter).not_to be_available
      end
    end
  end

  describe '#create_voucher' do
    it 'sends the fee, the candidate and the dates KuickPay needs, and returns the voucher number' do
      requests = []
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid(voucher_number: '0000832249220', requests:)

        voucher = adapter.create_voucher(payment:, candidate:, expires_on: Date.new(2026, 11, 4))

        expect(voucher).to have_attributes(consumer_number: '0000832249220', system_voucher_number: '234')
      end
      request = requests.first
      body = JSON.parse(request.body)
      expect(request.path).to eq('/api/insertPPMVoucher')
      expect([request['username'], request['password']]).to eq(%w[test-hybrid-user test-hybrid-password])
      expect(body).to include(
        'institutionID' => '00008', 'registrationNumber' => 'PAY-REF-1', 'head1' => 'Fee', 'amount1' => 1500,
        'totalAmount' => 1500, 'amountAfterDueDate' => 1500, 'dueDate' => '2026-11-04', 'expiryDate' => '2026-11-04',
        'name' => 'Ayesha Khan', 'mobile' => '03001234567', 'email' => 'no-reply@descon-mps.com'
      )
    end

    it 'refuses a fee that is not a whole number of rupees' do
      payment.update!(amount: BigDecimal('1500.50'))
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid

        expect { adapter.create_voucher(payment:, candidate:, expires_on: Date.current) }
          .to raise_error(PaymentCheckoutUnavailableError)
      end
    end

    it 'fails cleanly when KuickPay refuses, or is not configured' do
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid(insert_code: '05')

        expect { adapter.create_voucher(payment:, candidate:, expires_on: Date.current) }
          .to raise_error(PaymentCheckoutUnavailableError)
      end
      expect { adapter.create_voucher(payment:, candidate:, expires_on: Date.current) }
        .to raise_error(PaymentCheckoutUnavailableError)
    end

    it 'fails cleanly on an unreadable answer or a network error' do
      with_kuickpay_voucher_configured do
        allow(Net::HTTP).to receive(:start).and_raise(Timeout::Error)
        expect { adapter.create_voucher(payment:, candidate:, expires_on: Date.current) }
          .to raise_error(PaymentCheckoutUnavailableError)

        garbled = Net::HTTPOK.new('1.1', '200', 'OK')
        allow(garbled).to receive(:body).and_return('<html>')
        allow(Net::HTTP).to receive(:start) { |*, &block| block.call(instance_double(Net::HTTP, request: garbled)) }
        expect { adapter.create_voucher(payment:, candidate:, expires_on: Date.current) }
          .to raise_error(PaymentCheckoutUnavailableError)
      end
    end

    it 'fails when the answer has no voucher number' do
      with_kuickpay_voucher_configured do
        ok = Net::HTTPOK.new('1.1', '200', 'OK')
        allow(ok).to receive(:body).and_return({ response_Code: '00' }.to_json)
        allow(Net::HTTP).to receive(:start) { |*, &block| block.call(instance_double(Net::HTTP, request: ok)) }

        expect { adapter.create_voucher(payment:, candidate:, expires_on: Date.current) }
          .to raise_error(PaymentCheckoutUnavailableError)
      end
    end
  end

  describe '#settlements_on' do
    it "returns the day's settled transactions and ignores unsettled or malformed ones" do
      requests = []
      rows = [
        kuickpay_settlement(consumer_number: '0000811111', amount: 1500),
        kuickpay_settlement(consumer_number: '0000822222', amount: 1500, settled: false),
        kuickpay_settlement(consumer_number: '', amount: 1500),
        kuickpay_settlement(consumer_number: '0000833333', amount: 1).merge(amountTransaction: 'abc')
      ]
      with_kuickpay_voucher_configured do
        stub_kuickpay_hybrid(settlements: rows, requests:)

        result = adapter.settlements_on(date: Date.new(2026, 10, 21))

        expect(result.map(&:consumer_number)).to eq(['0000811111'])
        expect(result.first).to have_attributes(amount: BigDecimal('1500'), auth_id: '788895', bank: 'TMF')
      end
      expect(JSON.parse(requests.first.body)).to eq('institutionID' => '00008', 'transactionDate' => '20261021')
    end

    it 'is refused when voucher payments are not configured' do
      expect { adapter.settlements_on(date: Date.current) }.to raise_error(PaymentCheckoutUnavailableError)
    end
  end
end
