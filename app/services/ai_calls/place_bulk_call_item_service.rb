# frozen_string_literal: true

module AiCalls
  # Places the call for one candidate of a bulk batch (run by
  # AiCalls::PlaceBulkCallItemJob). The item row is locked while it is
  # processed, so a repeated run does nothing. Every outcome is recorded on the
  # item: `placed` (linked to the call), `skipped` (the candidate or the
  # situation made a call wrong right now -- they can be picked again by a later
  # batch) or `failed` (RoboCall could not take it, also pick-again-able).
  class PlaceBulkCallItemService < ApplicationService
    SKIP_REASONS = {
      AiCallOutsideCallingHoursError => 'outside_calling_hours',
      AiCallDailyLimitReachedError => 'daily_limit_reached',
      AiCallOutboundDisabledError => 'calling_disabled',
      InactiveAccountError => 'candidate_inactive',
      NoCurrentAssignmentError => 'no_assignment'
    }.freeze

    def initialize(item_id:, request_id:, configuration: AiCalls::Configuration.new)
      @item_id = item_id
      @request_id = request_id
      @configuration = configuration
    end

    def call
      BulkCallBatchItem.transaction do
        item = BulkCallBatchItem.lock.find(@item_id)
        process(item) if item.status == 'queued'
        item
      end
    end

    private

    def process(item)
      reason = unfit_reason(item)
      return item.update!(status: 'skipped', skip_reason: reason) if reason

      item.update!(status: 'placed', candidate_ai_call: place_call(item))
    rescue *SKIP_REASONS.keys => e
      item.update!(status: 'skipped', skip_reason: SKIP_REASONS.fetch(e.class))
    rescue AiCallProviderRequestError, AiCallProviderUnavailableError
      item.update!(status: 'failed', skip_reason: 'provider_error')
    end

    # The candidate may have moved on, or been deactivated, since the batch was started.
    def unfit_reason(item)
      candidate = item.candidate
      return 'candidate_inactive' unless candidate.active?

      'stage_changed' unless candidate.status_code == item.bulk_call_batch.workflow_stage_code
    end

    # A savepoint, so a provider failure rolls back the call's own records but not the item update.
    def place_call(item)
      batch = item.bulk_call_batch
      BulkCallBatchItem.transaction(requires_new: true) do
        TriggerOutboundCallService.new(
          candidate: item.candidate, plan: OutboundCallPlan.for_bulk(voice_id: batch.provider_voice_id),
          request_id: @request_id, actor: batch.created_by, configuration: @configuration
        ).call
      end
    end
  end
end
