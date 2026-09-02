# frozen_string_literal: true

class CandidateImportRowResult < ApplicationRecord
  STATUSES = %w[accepted rejected skipped committed].freeze

  belongs_to :candidate_import_batch

  validates :row_number,
            numericality: { only_integer: true, greater_than: 1 },
            uniqueness: { scope: :candidate_import_batch_id }
  validates :status, inclusion: { in: STATUSES }
  validates :error_field, :error_code, presence: true, if: :requires_error_details?

  private

  def requires_error_details?
    rejected? || skipped?
  end

  def rejected? = status == 'rejected'
  def skipped? = status == 'skipped'
end
