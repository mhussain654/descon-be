# frozen_string_literal: true

class CandidateDocumentSubmissionItem < ApplicationRecord
  include ImmutableRecord

  belongs_to :candidate_document_submission
  belongs_to :candidate_document

  before_validation :normalize_requirement_code

  validates :requirement_code, presence: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :required, inclusion: { in: [true, false] }

  private

  def normalize_requirement_code
    self.requirement_code = requirement_code.to_s.strip.downcase
  end
end
