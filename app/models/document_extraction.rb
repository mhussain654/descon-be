# frozen_string_literal: true

class DocumentExtraction < ApplicationRecord
  STATUSES = %w[pending succeeded failed].freeze

  belongs_to :candidate_document

  validates :provider, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :latest_first, -> { order(created_at: :desc) }

  def succeeded? = status == 'succeeded'

  def failed? = status == 'failed'

  def pending? = status == 'pending'
end
