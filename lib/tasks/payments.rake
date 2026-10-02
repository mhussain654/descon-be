# frozen_string_literal: true

namespace :payments do
  namespace :kuickpay do
    desc 'Calls KuickPay\'s Verify Status API for one payment (by its public_id), the 4th step of ' \
         'their documented hosted-checkout flow (Create Session -> Redirect -> Handle Return -> ' \
         'Verify Status). Prints the exact request/response so it can be shared with KuickPay while ' \
         'their Status API response shape is unconfirmed -- the same request/response is also logged ' \
         'via Rails.logger by the adapter itself. Applies a payment state change only if the response ' \
         'can be confidently read as carrying a status/outcome; otherwise the payment is left untouched ' \
         'and the raw response is still recorded as a PaymentEvent for review.'
    task :verify_status, [:public_id] => :environment do |_task, args|
      public_id = args[:public_id]
      abort('Usage: bin/rails "payments:kuickpay:verify_status[<payment_public_id>]"') if public_id.blank?

      payment = Payment.find_by(public_id:)
      abort("No payment found with public_id #{public_id}") if payment.blank?
      unless payment.provider_code == 'kuickpay'
        abort("Payment #{public_id} is not a KuickPay payment (provider_code: #{payment.provider_code.inspect})")
      end

      response = Payments::VerifyPaymentStatusService.call(payment:, request_id: "rake:#{SecureRandom.uuid}")
      puts "HTTP status: #{response.http_status}"
      puts "Response body: #{response.body.is_a?(String) ? response.body : response.body.to_json}"
      payment.reload
      puts "Payment #{payment.public_id} status_code is now: #{payment.status_code}"
    rescue BaseError => e
      abort("Failed: #{e.class}: #{e.message}")
    end
  end
end
