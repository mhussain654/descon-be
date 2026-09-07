# frozen_string_literal: true

# Links one uploaded document to a submission batch, recording which document requirement
# it was meant to satisfy and whether that requirement is mandatory.
class CandidateDocumentSubmissionItem < ApplicationRecord
  include ImmutableRecord

  belongs_to :candidate_document_submission
  belongs_to :candidate_document

  before_validation :normalize_requirement_code

  validates :requirement_code, presence: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :required, inclusion: { in: [true, false] }

  private

  # Trims and lowercases the requirement code.
  def normalize_requirement_code
    self.requirement_code = requirement_code.to_s.strip.downcase
  end
end
