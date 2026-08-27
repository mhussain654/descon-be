# frozen_string_literal: true

class CandidateDocumentSubmission < ApplicationRecord
  include ImmutableRecord

  STATUS_CODES = %w[submitted].freeze

  belongs_to :candidate_assignment
  delegate :candidate, to: :candidate_assignment

  before_validation :assign_public_id, on: :create
  before_validation :normalize_status_code

  validates :public_id, presence: true, uniqueness: true
  validates :status_code, presence: true, inclusion: { in: STATUS_CODES }
  validates :submitted_at, presence: true

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def normalize_status_code
    self.status_code = status_code.to_s.strip.downcase.presence || 'submitted'
  end
end
