# frozen_string_literal: true

# The column default ('preflighted') was never a member of
# CandidateImportBatch::STATUSES (queued/processing/completed/partial/failed/
# invalidated) or of this table's own check constraint -- so any row created
# without an explicit `status:` (the DB default kicking in) always failed
# model validation, and would have failed the check constraint too even
# bypassing the model. The only real creation path
# (Admin::Candidates::Imports::PreflightService) already always passes
# `status: 'queued'` explicitly, confirming 'queued' -- not 'preflighted' --
# is the actually-intended initial state; this migration just makes the
# column default match what the application, model and constraint already
# agree on.
class FixCandidateImportBatchesStatusDefault < ActiveRecord::Migration[8.1]
  def up
    change_column_default :candidate_import_batches, :status, from: 'preflighted', to: 'queued'
  end

  def down
    change_column_default :candidate_import_batches, :status, from: 'queued', to: 'preflighted'
  end
end
