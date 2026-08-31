# frozen_string_literal: true

module Payments
  class EligibilityResultBuilder < ApplicationService
    Params = Struct.new(
      :candidate,
      :configuration,
      :assignment,
      :current_stage_code,
      :eligible,
      :blocking_reasons,
      :checkout_available,
      keyword_init: true
    )

    def initialize(**params) = @params = Params.new(**params)

    def call
      Payments::EligibilityResult.new(
        **base_attributes,
        **stage_attributes,
        **payment_attributes,
        latest_payment: latest_payment
      )
    end

    private

    def base_attributes
      {
        candidate: @params.candidate,
        assignment: @params.assignment,
        eligible: @params.eligible,
        checkout_available: @params.checkout_available,
        blocking_reasons: @params.blocking_reasons
      }
    end

    def stage_attributes
      {
        required_stage_code: 'fee_pending',
        current_stage_code: @params.current_stage_code
      }
    end

    def payment_attributes
      {
        amount: @params.configuration.amount,
        currency_code: @params.configuration.currency_code
      }
    end

    def latest_payment
      return if @params.assignment.blank?

      @params.assignment.payments.latest_first.first
    end
  end
end
