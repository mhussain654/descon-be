# frozen_string_literal: true

module Payments
  class CheckoutSessionService < ApplicationService
    def initialize(candidate:, request_id:, provider_code: nil)
      @candidate = candidate
      @request_id = request_id
      @configuration = Payments::Configuration.new
      @provider_code = provider_code
    end

    def call
      raise PaymentCheckoutUnavailableError unless provider.available?

      CandidateAssignment.transaction { execute_checkout }
    rescue Payments::ProviderNotConfiguredError
      raise PaymentCheckoutUnavailableError
    end

    private

    def execute_checkout
      candidate, assignment = locked_candidate_and_assignment
      ensure_checkout_eligible!(candidate:)
      ensure_fee_pending!(candidate:, assignment:)

      existing_payment = reusable_payment_for(assignment)
      return response_for(existing_payment, replayed: true) if existing_payment.present?

      payment = create_payment!(assignment:)
      session = create_checkout_session(payment:, candidate:, assignment:)
      persist_checkout_session!(payment:, assignment:, session:)
      response_for(payment)
    end

    def locked_candidate_and_assignment
      candidate = Candidate.lock.find(@candidate.id)
      raise InactiveAccountError unless candidate.active?

      assignment = candidate.current_assignment
      raise NoCurrentAssignmentError if assignment.blank?

      assignment.lock!
      [candidate, assignment]
    end

    def ensure_checkout_eligible!(candidate:)
      eligibility = Payments::EligibilityService.call(candidate:, provider_code: provider.provider_code)
      return if eligibility.eligible

      raise PaymentNotEligibleError.new(details: { blocking_reasons: eligibility.blocking_reasons })
    end

    def ensure_fee_pending!(candidate:, assignment:)
      return unless assignment.current_workflow_stage.code == 'verified'

      CandidateWorkflows::TransitionService.call(
        actor: nil,
        candidate:,
        to_stage_code: 'fee_pending',
        request_id: "#{@request_id}:fee_pending",
        validate_permissions: false
      )
      assignment.reload
    end

    def reusable_payment_for(assignment)
      assignment.payments.latest_first.find do |payment|
        payment.checkout_pending? &&
          payment.provider_code == provider.provider_code &&
          payment.checkout_url.present? &&
          payment.checkout_expires_at.present? && payment.checkout_expires_at.future?
      end
    end

    def create_checkout_session(payment:, candidate:, assignment:)
      provider.create_checkout_session(
        payment:,
        candidate:,
        assignment:,
        amount: @configuration.amount,
        currency_code: @configuration.currency_code
      )
    end

    def create_payment!(assignment:)
      assignment.payments.create!(
        payment_type_code: 'onboarding_fee',
        status_code: 'checkout_pending',
        amount: @configuration.amount,
        currency_code: @configuration.currency_code,
        provider_code: provider.provider_code,
        provider_order_id: generated_order_id(assignment)
      )
    end

    def persist_checkout_session!(payment:, assignment:, session:)
      Payments::CheckoutSessionPersister.call(
        payment:,
        assignment:,
        candidate: @candidate,
        request_id: @request_id,
        session:
      )
    end

    def generated_order_id(assignment)
      "PAY-#{assignment.reference_number}-#{SecureRandom.hex(6).upcase}"
    end

    def response_for(payment, replayed: false)
      {
        payment: payment.reload,
        eligibility: Payments::EligibilityService.call(candidate: @candidate, provider_code: provider.provider_code),
        replayed:
      }
    end

    def provider
      @provider ||= Payments::ProviderRegistry.fetch(@provider_code)
    end
  end
end
