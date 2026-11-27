# frozen_string_literal: true

module Payments
  module Providers
    # KuickPay's insert-voucher reply returns its reference number with the institution code in front
    # (10420 + 261105039065). This strips that code, giving the number KuickPay's portal shows in its
    # "ReferenceNumber" column. A value that does not start with the code is kept as it is.
    module KuickpayReferenceNumber
      module_function

      def without_institution(returned, institution_id)
        text = returned.to_s
        prefix = institution_id.to_s
        return text unless prefix.present? && text.start_with?(prefix) && text.length > prefix.length

        text.delete_prefix(prefix)
      end
    end
  end
end
