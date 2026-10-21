# frozen_string_literal: true

module AiCalls
  # Places the call for one candidate of a bulk batch; see
  # AiCalls::PlaceBulkCallItemService. Enqueued by
  # AiCalls::StartBulkCallBatchService, spaced out per candidate.
  class PlaceBulkCallItemJob < ApplicationJob
    queue_as :default

    # An unexpected error must not leave the candidate `queued` forever (a queued
    # candidate counts as already called). Marked failed -- so a later batch can
    # pick them again -- and re-raised so the bug stays visible.
    rescue_from(StandardError) do |error|
      BulkCallBatchItem.where(id: arguments.first, status: 'queued').find_each do |item|
        item.update!(status: 'failed', skip_reason: 'provider_error')
      end
      raise error
    end

    # Declared after the catch-all above on purpose: handlers declared later
    # take priority, so a vanished item is dropped, not marked failed.
    discard_on ActiveRecord::RecordNotFound

    def perform(item_id)
      PlaceBulkCallItemService.new(item_id:, request_id: SecureRandom.uuid).call
    end
  end
end
