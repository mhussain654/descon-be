# frozen_string_literal: true

# Tracks a single OCR/data-extraction attempt run against an uploaded candidate document
# (e.g. reading a passport or CNIC number), including which provider ran it and its outcome.
class DocumentExtraction < ApplicationRecord
  STATUSES = %w[pending succeeded failed].freeze

  belongs_to :candidate_document

  validates :provider, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :latest_first, -> { order(created_at: :desc) }

  # True if the extraction attempt completed successfully.
  def succeeded? = status == 'succeeded'

  # True if the extraction attempt failed.
  def failed? = status == 'failed'

  # True if the extraction attempt has not yet finished.
  def pending? = status == 'pending'
end
