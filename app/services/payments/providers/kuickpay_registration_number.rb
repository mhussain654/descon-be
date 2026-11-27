# frozen_string_literal: true

module Payments
  module Providers
    # KuickPay pays a voucher by institution code + registration number (e.g. 10420 + 500002). The registration
    # number is the client's own registration (file) number for the candidate, sent exactly as entered, as their
    # other system and KuickPay's portal do. It is unique across the organisation and digits only (wallets such
    # as Easypaisa take nothing else). A voucher is never created without one.
    module KuickpayRegistrationNumber
      module_function

      def for(assignment)
        number = assignment.registration_number
        raise RegistrationNumberMissingError if number.blank?

        number.to_s
      end
    end
  end
end
