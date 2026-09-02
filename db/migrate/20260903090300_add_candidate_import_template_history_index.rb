# frozen_string_literal: true

class AddCandidateImportTemplateHistoryIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :candidate_import_batches, %i[template_version created_at], algorithm: :concurrently
  end
end
