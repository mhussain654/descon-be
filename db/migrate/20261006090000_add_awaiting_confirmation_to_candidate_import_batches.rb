# frozen_string_literal: true

# A preflight (preview) used to be stored as `queued`, the same status as an
# import the staff member had actually confirmed, so unconfirmed previews
# showed up in import history as queued imports. Previews now have their own
# status until confirmed. Existing previews (never enqueued) are moved over.
class AddAwaitingConfirmationToCandidateImportBatches < ActiveRecord::Migration[8.1]
  STATUSES = %w[queued processing completed partial failed invalidated].freeze

  def up
    remove_check_constraint :candidate_import_batches, name: 'candidate_import_batches_status'
    add_status_constraint(['awaiting_confirmation', *STATUSES])
    execute <<~SQL.squish
      UPDATE candidate_import_batches SET status = 'awaiting_confirmation'
      WHERE status = 'queued' AND enqueued_at IS NULL
    SQL
    change_column_default :candidate_import_batches, :status, from: 'queued', to: 'awaiting_confirmation'
  end

  def down
    change_column_default :candidate_import_batches, :status, from: 'awaiting_confirmation', to: 'queued'
    execute "UPDATE candidate_import_batches SET status = 'queued' WHERE status = 'awaiting_confirmation'"
    remove_check_constraint :candidate_import_batches, name: 'candidate_import_batches_status'
    add_status_constraint(STATUSES)
  end

  private

  def add_status_constraint(statuses)
    add_check_constraint :candidate_import_batches,
                         "status IN (#{statuses.map { |status| connection.quote(status) }.join(', ')})",
                         name: 'candidate_import_batches_status'
  end
end
