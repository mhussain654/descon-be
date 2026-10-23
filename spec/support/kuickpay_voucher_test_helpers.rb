# frozen_string_literal: true

# Helpers for the KuickPay voucher (Hybrid API) payments, which never reach the real
# KuickPay: Net::HTTP is stubbed. Separate from KuickpayTestHelpers, which covers the
# hosted card checkout.
module KuickpayVoucherTestHelpers
  KUICKPAY_VOUCHER_TEST_ENV = { 'KUICKPAY_VOUCHER_ENABLED' => 'true', 'KUICKPAY_INSTITUTION_ID' => '00008' }.freeze

  # The voucher (Hybrid API) feature on: its own switch and institution id. The
  # username/password are the fixed fakes in config/kuickpay.yml's test block.
  def with_kuickpay_voucher_configured
    original = ENV.to_h.slice(*KUICKPAY_VOUCHER_TEST_ENV.keys)
    ENV.update(KUICKPAY_VOUCHER_TEST_ENV)
    yield
  ensure
    KUICKPAY_VOUCHER_TEST_ENV.each_key { |key| ENV[key] = original[key] }
  end

  # Stubs Net::HTTP for both Hybrid calls, told apart by request path. `requests`
  # collects every request made, so a spec can look at what was sent.
  def stub_kuickpay_hybrid(voucher_number: '0000832249220', settlements: [], insert_code: '00', requests: [])
    allow(Net::HTTP).to receive(:start) do |*, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |request|
        requests << request
        kuickpay_hybrid_response(request.path, voucher_number:, settlements:, insert_code:)
      end
      block.call(http)
    end
  end

  def kuickpay_hybrid_response(path, voucher_number:, settlements:, insert_code:)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    body = if path.end_with?('/insertPPMVoucher')
             { response_Code: insert_code, response_description: voucher_number, response_detail: '234' }
           else
             { response_Code: '00', transactionList: settlements, count: settlements.size.to_s }
           end
    allow(response).to receive(:body).and_return(body.to_json)
    response
  end

  def kuickpay_settlement(consumer_number:, amount:, auth_id: '788895', settled: true)
    { consumer_Number: consumer_number, registrationNumber: '', transaction_Date_Time: '2026-10-21T10:00:00',
      settlement_Date_Time: '2026-10-21T10:00:05', amountTransaction: amount.to_f, authID: auth_id, bank: 'TMF',
      isSettled: settled }
  end
end

RSpec.configure do |config|
  config.include KuickpayVoucherTestHelpers, type: :request
  config.include KuickpayVoucherTestHelpers, file_path: %r{spec/(services|jobs)/payments}
end
