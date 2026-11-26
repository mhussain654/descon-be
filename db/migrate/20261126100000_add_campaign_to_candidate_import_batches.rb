# frozen_string_literal: true

# Each candidate import now goes into a chosen candidate campaign: the import
# records which one, and every candidate it creates is put in it.
class AddCampaignToCandidateImportBatches < ActiveRecord::Migration[8.1]
  def change
    add_reference :candidate_import_batches, :campaign, foreign_key: true
  end
end
