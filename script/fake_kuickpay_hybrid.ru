# frozen_string_literal: true

# LOCAL STAND-IN for KuickPay's "Hybrid" voucher API, so payment codes can be tried
# without KuickPay. Development only; keeps everything in memory.
#
#   bundle exec rackup script/fake_kuickpay_hybrid.ru -p 9292
#
# POST /api/insertPPMVoucher       -> hands out a voucher (consumer) number
# POST /api/BillPaymentBulkInquiry -> lists the vouchers that were "paid"
# GET  /pay/<voucher number>       -> pretends the candidate paid that voucher
# GET  /                           -> shows every voucher and whether it is paid
require 'json'
require 'securerandom'

class FakeKuickpayHybrid
  Voucher = Struct.new(:consumer_number, :registration_number, :amount, :paid, keyword_init: true)

  def initialize
    @vouchers = {}
    @mutex = Mutex.new
  end

  def call(env)
    request = Rack::Request.new(env)
    @mutex.synchronize { route(request) }
  end

  private

  def route(request)
    case [request.request_method, request.path_info]
    in ['POST', '/api/insertPPMVoucher'] then issue_voucher(JSON.parse(request.body.read))
    in ['POST', '/api/BillPaymentBulkInquiry'] then inquiry
    in ['GET', %r{\A/pay/(\d+)\z}] then pay(Regexp.last_match(1))
    in ['GET', '/'] then json(200, @vouchers.values.map(&:to_h))
    else json(404, error: 'not found')
    end
  end

  def issue_voucher(body)
    number = "0000#{SecureRandom.random_number(10**9).to_s.rjust(9, '0')}"
    @vouchers[number] = Voucher.new(consumer_number: number, registration_number: body['registrationNumber'],
                                    amount: body['totalAmount'], paid: false)
    json(200, response_Code: '00', response_description: number, response_detail: '1')
  end

  def inquiry
    paid = @vouchers.values.select(&:paid).map { |voucher| transaction_for(voucher) }
    json(200, response_Code: '00', transactionList: paid, count: format('%02d', paid.size))
  end

  def pay(number)
    voucher = @vouchers[number]
    return json(404, error: 'unknown voucher') unless voucher

    voucher.paid = true
    json(200, paid: number, amount: voucher.amount)
  end

  def transaction_for(voucher)
    now = Time.now.getlocal.strftime('%Y-%m-%dT%H:%M:%S')
    { consumer_Number: voucher.consumer_number, registrationNumber: voucher.registration_number,
      transaction_Date_Time: now, settlement_Date_Time: now, amountTransaction: voucher.amount.to_f,
      authID: voucher.consumer_number[-6..], bank: 'FAKE', isSettled: true }
  end

  def json(status, body)
    [status, { 'content-type' => 'application/json' }, [JSON.generate(body)]]
  end
end

run FakeKuickpayHybrid.new
