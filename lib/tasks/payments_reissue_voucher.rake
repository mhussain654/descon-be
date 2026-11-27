# frozen_string_literal: true

namespace :payments do
  namespace :kuickpay do
    desc 'Replaces an unpaid KuickPay voucher (by its old Kuickpay ID) with a new one and has KuickPay text the ' \
         'candidate the new Kuickpay ID. For vouchers issued before Kuickpay IDs were built from the ' \
         'registration number. Delete the old voucher in KuickPay\'s portal afterwards.'
    task :reissue_voucher, [:voucher_number] => :environment do |_task, args|
      voucher_number = args[:voucher_number]
      abort('Usage: bin/rails "payments:kuickpay:reissue_voucher[<old Kuickpay ID>]"') if voucher_number.blank?

      payment = Payment.where(provider_code: 'kuickpay_voucher', voucher_number:, status_code: 'checkout_pending')
                       .order(created_at: :desc).first
      abort("No unpaid KuickPay voucher with Kuickpay ID #{voucher_number}") if payment.blank?

      result = Payments::ReissueVoucherService.call(payment:)
      puts "Old voucher #{result.old_payment.voucher_number} is now #{result.old_payment.status_code}."
      new_payment = result.new_payment
      expires_on = new_payment.checkout_expires_at.in_time_zone('Asia/Karachi').to_date
      puts "New Kuickpay ID: #{new_payment.voucher_number} " \
           "(due #{new_payment.voucher_due_on}, payable until #{expires_on})."
      puts 'KuickPay has been asked to text it.' if result.sms_sent
      puts 'KuickPay refused the SMS: tell the candidate the new Kuickpay ID.' unless result.sms_sent
    rescue ArgumentError, BaseError => e
      abort("Failed: #{e.message}")
    end
  end
end
