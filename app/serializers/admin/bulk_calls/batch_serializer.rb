# frozen_string_literal: true

module Admin
  module BulkCalls
    # One bulk-call batch with its per-status item counts. `counts` is passed in
    # (grouped for the whole page by the controller) so a list never runs one
    # count query per batch.
    class BatchSerializer
      def initialize(batch, counts:)
        @batch = batch
        @counts = counts
      end

      def as_json(*)
        identity.merge(
          counts: BulkCallBatchItem::STATUSES.index_with { |status| @counts.fetch(status, 0) },
          created_by: { id: @batch.created_by.public_id, role: @batch.created_by.role },
          created_at: @batch.created_at.utc.iso8601
        )
      end

      private

      def identity
        {
          id: @batch.public_id,
          voice: { id: @batch.robocall_voice.public_id, name: @batch.voice_name },
          workflow_stage_code: @batch.workflow_stage_code, filters: @batch.filters,
          requested_limit: @batch.requested_limit, selected_count: @batch.selected_count
        }
      end
    end
  end
end
