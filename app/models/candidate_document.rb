# frozen_string_literal: true

# One logical document a candidate submits against a requirement (e.g. their passport or
# CNIC), tracked through upload, verification/rejection, and versioning when replaced. Its
# physical files (passport pages, CNIC front/back, several certificates...) are its `files`;
# review is always of the whole file set.
class CandidateDocument < ApplicationRecord
  include CandidateDocuments::PoliceCharacterCompliance

  STATUS_CODES = %w[uploaded under_verification verified rejected].freeze
  API_STATUS_MAP = {
    'uploaded' => 'uploaded',
    'under_verification' => 'pending_review',
    'verified' => 'verified',
    'rejected' => 'rejected'
  }.freeze
  REPLACEABLE_STATUS_CODES = %w[uploaded rejected].freeze

  belongs_to :candidate_assignment
  belongs_to :document_type
  belongs_to :uploaded_by, class_name: 'User', optional: true
  belongs_to :verified_by, class_name: 'User', optional: true
  has_one :submission_item, class_name: 'CandidateDocumentSubmissionItem', dependent: :restrict_with_exception
  has_one :candidate_document_submission, through: :submission_item
  has_many :document_extractions, dependent: :destroy
  has_many :files, -> { order(:position) }, class_name: 'CandidateDocumentFile', inverse_of: :candidate_document,
                                            dependent: :destroy

  before_validation :assign_public_id, on: :create
  before_validation :normalize_status_code

  scope :current_version, -> { where(superseded_at: nil) }

  validates :public_id, presence: true, uniqueness: true
  validates :status_code, presence: true, inclusion: { in: STATUS_CODES }
  validates :uploaded_at, presence: true
  validate :files_present_for_current_version
  validate :status_consistency

  # The document's status translated to the external API's vocabulary.
  def api_status = API_STATUS_MAP.fetch(status_code)

  # Whether the candidate is allowed to upload a new file to replace this one.
  def replacement_allowed? = REPLACEABLE_STATUS_CODES.include?(status_code)

  # Whether this row is the active document version (not yet replaced by a newer upload).
  def current_version? = superseded_at.blank?

  # The file that best represents the whole document: a combined PDF, else page 1 / the
  # front, else the first uploaded file.
  def primary_file
    CandidateDocumentFile::PRIMARY_SIDE_PRIORITY.each do |side_code|
      match = files.find { |file| file.side_code == side_code }
      return match if match
    end
    files.min_by(&:position)
  end

  def total_byte_size = files.sum(&:byte_size)

  # The file a preview/download request names (by its public id), or the
  # representative file when none is named; nil for an id outside this document.
  # Loaded on its own with its attachment, since only this one file is served.
  def file_for_access(file_public_id)
    chosen = file_public_id.blank? ? primary_file : files.find { |file| file.public_id == file_public_id.to_s }
    chosen && CandidateDocumentFile.includes(file_attachment: :blob).find(chosen.id)
  end

  private

  # Assigns a public-facing UUID identifier on creation, if one isn't already set.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  # Trims and lowercases the status code.
  def normalize_status_code
    self.status_code = status_code.to_s.strip.downcase
  end

  # Enforces that the verification-related fields match what's expected for the current status.
  def status_consistency
    case status_code
    when 'uploaded', 'under_verification'
      require_unreviewed_state
    when 'verified'
      require_verified_state
    when 'rejected'
      require_rejected_state
    end
  end

  # Adds a presence error on the attribute when the given value is blank.
  def require_present(attribute, value)
    errors.add(attribute, :blank) if value.blank?
  end

  # Adds a "must be blank" error on the attribute when the given value is present.
  def require_absent(attribute, value)
    errors.add(attribute, :present) if value.present?
  end

  # Uploaded/under-review documents must not yet carry any verification or rejection data.
  def require_unreviewed_state
    require_absent(:verified_by, verified_by_id)
    require_absent(:verified_at, verified_at)
    require_absent(:rejection_reason, rejection_reason)
  end

  # Verified documents must record who verified them and when, with no rejection reason.
  def require_verified_state
    require_present(:verified_by, verified_by_id)
    require_present(:verified_at, verified_at)
    require_absent(:rejection_reason, rejection_reason)
  end

  # Rejected documents must record who reviewed them, when, and why they were rejected.
  def require_rejected_state
    require_present(:verified_by, verified_by_id)
    require_present(:verified_at, verified_at)
    require_present(:rejection_reason, rejection_reason)
  end

  # The current (non-superseded) version must always have at least one file.
  def files_present_for_current_version
    return unless current_version?
    return if files.any?

    errors.add(:files, :blank)
  end
end
