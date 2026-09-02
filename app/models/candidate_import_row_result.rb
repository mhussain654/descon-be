# frozen_string_literal: true

class CandidateImportRowResult < ApplicationRecord
  STATUSES = %w[accepted rejected skipped committed].freeze

  belongs_to :candidate_import_batch

  validates :row_number,
            numericality: { only_integer: true, greater_than: 1 },
            uniqueness: { scope: :candidate_import_batch_id }
  validates :status, inclusion: { in: STATUSES }
end
