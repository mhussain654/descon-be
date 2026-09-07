# frozen_string_literal: true

# The outcome of processing a single row from a candidate import batch's CSV file.
class CandidateImportRowResult < ApplicationRecord
  STATUSES = %w[accepted rejected skipped committed].freeze

  belongs_to :candidate_import_batch

  validates :row_number,
            numericality: { only_integer: true, greater_than: 1 },
            uniqueness: { scope: :candidate_import_batch_id }
  validates :status, inclusion: { in: STATUSES }
  validates :error_field, :error_code, presence: true, if: :requires_error_details?

  private

  # Whether this row's status requires an accompanying error field and code.
  def requires_error_details?
    rejected? || skipped?
  end

  # Whether the row failed validation and was not imported.
  def rejected? = status == 'rejected'
  # Whether the row was intentionally left out of the import (e.g. a duplicate).
  def skipped? = status == 'skipped'
end
