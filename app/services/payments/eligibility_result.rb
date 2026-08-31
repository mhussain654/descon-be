# frozen_string_literal: true

module Payments
  EligibilityResult = Struct.new(
    :candidate,
    :assignment,
    :eligible,
    :checkout_available,
    :blocking_reasons,
    :required_stage_code,
    :current_stage_code,
    :amount,
    :currency_code,
    :latest_payment,
    keyword_init: true
  )
end
