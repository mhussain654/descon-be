# frozen_string_literal: true

# An immutable record of a candidate submitting a batch of required documents together
# for an assignment, at a single point in time.
class CandidateDocumentSubmission < ApplicationRecord
  include ImmutableRecord

  STATUS_CODES = %w[submitted].freeze

  belongs_to :candidate_assignment
  has_many :submission_items, class_name: 'CandidateDocumentSubmissionItem', dependent: :destroy
  has_many :candidate_documents, through: :submission_items

  delegate :candidate, to: :candidate_assignment

  before_validation :assign_public_id, on: :create
  before_validation :normalize_status_code

  validates :public_id, presence: true, uniqueness: true
  validates :status_code, presence: true, inclusion: { in: STATUS_CODES }
  validates :submitted_at, presence: true

  private

  # Assigns a public-facing UUID identifier on creation, if one isn't already set.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  # Trims and lowercases the status code, defaulting to 'submitted' when blank.
  def normalize_status_code
    self.status_code = status_code.to_s.strip.downcase.presence || 'submitted'
  end
end
