# frozen_string_literal: true

# The rejected cell behind a row's error (see Admin::Candidates::Imports::
# RejectedValue), so the import detail page and error report can show what
# to fix. Only ever that one column's value, with identity numbers masked.
class AddErrorValueToCandidateImportRowResults < ActiveRecord::Migration[8.1]
  def change
    add_column :candidate_import_row_results, :error_value, :string
  end
end
