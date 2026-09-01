# frozen_string_literal: true

module Payments
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
      build_result(
        assignment:,
        current_stage_code: assignment.current_workflow_stage.code,
        eligible: prerequisite_result.allowed,
        blocking_reasons: prerequisite_result.blocking_reasons,
        checkout_available: prerequisite_result.allowed && provider.available?
      )
    end

    def unavailable_provider_result
      assignment = @candidate.current_assignment
      ineligible_result(
        assignment:,
        current_stage_code: assignment&.current_workflow_stage&.code,
        blocking_reasons: ['payment_provider_unavailable']
      )
    end

    def build_result(assignment:, current_stage_code:, eligible:, blocking_reasons:, checkout_available:)
      Payments::EligibilityResultBuilder.call(
        candidate: @candidate,
        configuration: @configuration,
        assignment:,
        current_stage_code:,
        eligible:,
        blocking_reasons:,
        checkout_available:
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
      %w[verified fee_pending].include?(assignment.current_workflow_stage.code)
    end

    def provider
      @provider ||= Payments::ProviderRegistry.fetch(@provider_code)
    end

    def fee_paid_or_later?(assignment)
      assignment.current_workflow_stage.position >= WorkflowStage.find_by!(code: 'fee_paid').position
    end
  end
end
