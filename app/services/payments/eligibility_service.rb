# frozen_string_literal: true

module Payments
  # Payment opens only once the candidate reaches the Fee Pending stage of
  # their own process (its place differs per country), and closes for good
  # once they reach Fee Paid.
  class EligibilityService < ApplicationService
    def initialize(candidate:, provider_code: nil)
      @candidate = candidate
      @provider_code = provider_code
      @configuration = Payments::Configuration.new
    end

    def call
      assignment = @candidate.current_assignment
      return ineligible_result(assignment:, blocking_reasons: ['no_current_assignment']) if assignment.blank?

      return ineligible_result_for_stage(assignment:) unless stage_eligible?(assignment)

      eligible_result(assignment:)
    rescue Payments::ProviderNotConfiguredError
      unavailable_provider_result
    end

    private

    def ineligible_result(assignment:, blocking_reasons:, current_stage_code: assignment&.current_workflow_stage&.code)
      build_result(
        assignment:,
        current_stage_code:,
        eligible: false,
        blocking_reasons:,
        checkout_available: false
      )
    end

    def ineligible_result_for_stage(assignment:)
      reason = fee_paid_or_later?(assignment) ? 'payment_already_completed' : 'payment_stage_not_reached'
      ineligible_result(
        assignment:,
        current_stage_code: assignment.current_workflow_stage.code,
        blocking_reasons: [reason]
      )
    end

    def stage_eligible?(assignment)
      eligible_stage?(assignment) && !fee_paid_or_later?(assignment)
    end

    def eligible_result(assignment:)
      prerequisite_result = fee_pending_prerequisite_result(assignment)
      allowed = prerequisite_result.allowed
      build_result(
        assignment:, current_stage_code: assignment.current_workflow_stage.code, eligible: allowed,
        blocking_reasons: prerequisite_result.blocking_reasons,
        checkout_available: allowed && card_offered?, voucher_available: allowed && voucher_offered?
      )
    end

    # A way of paying is offered when the server is set up for it and App Settings has it on.
    def card_offered? = provider.available? && AppFeatureSetting.enabled?(:card_payment)
    def voucher_offered? = voucher_provider.available? && AppFeatureSetting.enabled?(:voucher_payment)

    def unavailable_provider_result
      assignment = @candidate.current_assignment
      ineligible_result(
        assignment:,
        current_stage_code: assignment&.current_workflow_stage&.code,
        blocking_reasons: ['payment_provider_unavailable']
      )
    end

    def build_result(assignment:, current_stage_code:, eligible:, blocking_reasons:, **availability)
      Payments::EligibilityResultBuilder.call(
        candidate: @candidate,
        configuration: @configuration,
        assignment:,
        current_stage_code:,
        eligible:,
        blocking_reasons:,
        checkout_available: availability.fetch(:checkout_available),
        voucher_available: availability.fetch(:voucher_available, false)
      )
    end

    def fee_pending_prerequisite_result(assignment)
      CandidateWorkflows::TransitionService.transition_prerequisite_result(
        candidate: @candidate,
        assignment:,
        destination_stage: WorkflowStage.find_by!(code: 'fee_pending')
      )
    end

    def eligible_stage?(assignment)
      assignment.current_workflow_stage.code == 'fee_pending'
    end

    def provider
      @provider ||= Payments::ProviderRegistry.fetch(@provider_code)
    end

    def voucher_provider
      @voucher_provider ||= Payments::ProviderRegistry.fetch('kuickpay_voucher')
    end

    def fee_paid_or_later?(assignment) = assignment.reached_stage?('fee_paid')
  end
end
