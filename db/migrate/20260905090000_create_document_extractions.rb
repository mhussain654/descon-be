# frozen_string_literal: true

# One row per OCR extraction attempt (MPS-404) against a CandidateDocument
# (passport/CNIC front/back/next-of-kin CNIC). Kept separate from
# CandidateDocument's own issued_on/expires_on columns deliberately: those
# two stay the single authoritative source of truth, written only when HR
# confirms a value through the verify action -- never directly by the
# extraction job -- so a failed or low-confidence extraction can never
# silently become the record of truth. The partial unique index enforces
# "at most one pending or succeeded attempt per document" at the database
# level, which the job relies on for its own idempotency guard (a duplicate
# job run raises RecordNotUnique and returns without retrying Textract) --
# a fresh attempt is still allowed after a prior one failed.
class CreateDocumentExtractions < ActiveRecord::Migration[8.1]
  def change
    create_extractions_table
    add_indexes
    add_constraints
  end

  private

  # One line per column reads far more clearly than splitting this table
  # definition across methods merely to satisfy a line-count metric.
  # rubocop:disable Metrics/MethodLength
  def create_extractions_table
    create_table :document_extractions do |table|
      table.references :candidate_document, null: false, foreign_key: true
      table.string :provider, null: false
      table.string :status, null: false, default: 'pending'
      table.date :extracted_issued_on
      table.date :extracted_expires_on
      table.decimal :confidence_issued_on, precision: 5, scale: 2
      table.decimal :confidence_expires_on, precision: 5, scale: 2
      table.jsonb :raw_response, null: false, default: {}
      table.text :error_message
      table.datetime :extracted_at
      table.timestamps
    end
  end
  # rubocop:enable Metrics/MethodLength

  def add_indexes
    add_index :document_extractions, :candidate_document_id,
              unique: true, where: "status IN ('pending', 'succeeded')",
              name: 'index_document_extractions_on_active_attempt'
  end

  def add_constraints
    add_check_constraint :document_extractions, "status IN ('pending', 'succeeded', 'failed')",
                         name: 'document_extractions_status'
  end
end
