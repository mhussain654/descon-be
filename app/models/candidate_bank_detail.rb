# frozen_string_literal: true

# A version of a candidate's bank account details (encrypted at rest) submitted with a proof
# document, superseded by a new row whenever the details are updated.
class CandidateBankDetail < ApplicationRecord
  STATUS_CODES = %w[submitted].freeze
  ACCOUNT_NUMBER_FORMAT = /\A[A-Z0-9]{4,34}\z/

  belongs_to :candidate_assignment
  belongs_to :reviewed_by, class_name: 'User', optional: true

  has_one_attached :proof

  encrypts :account_title, :account_number

  before_validation :assign_public_id, on: :create
  before_validation :normalize_account_title
  before_validation :normalize_account_number
  before_validation :normalize_bank_name
  before_validation :normalize_status_code
  before_validation :normalize_checksum

  scope :current_version, -> { where(superseded_at: nil) }

  validates :public_id, presence: true, uniqueness: true
  validates :status_code, presence: true, inclusion: { in: STATUS_CODES }
  validates :account_title, :account_number, :bank_name, :proof_filename, :proof_content_type, presence: true
  validates :proof_byte_size, numericality: { greater_than: 0 }
  validates :submitted_at, presence: true
  validates :account_number, format: { with: ACCOUNT_NUMBER_FORMAT }
  validate :proof_attached_for_current_version

  # Whether this row is the active bank detail version (not yet replaced by a newer submission).
  def current_version? = superseded_at.blank?

  # Whether the proof-of-account file has actually been uploaded and stored.
  def proof_accessible?
    proof.attached?
  end

  private

  # Assigns a public-facing UUID identifier on creation, if one isn't already set.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  # Trims and collapses internal whitespace in the account title.
  def normalize_account_title
    self.account_title = account_title.to_s.strip.squish
  end

  # Uppercases the account number and removes whitespace, blanking it out if empty.
  def normalize_account_number
    normalized_value = account_number.to_s.upcase.gsub(/\s+/, '')
    self.account_number = normalized_value.presence
  end

  # Trims and collapses internal whitespace in the bank name.
  def normalize_bank_name
    self.bank_name = bank_name.to_s.strip.squish
  end

  # Trims and lowercases the status code, defaulting to 'submitted' when blank.
  def normalize_status_code
    self.status_code = status_code.to_s.strip.downcase.presence || 'submitted'
  end

  # Trims and lowercases the proof file's stored checksum.
  def normalize_checksum
    self.proof_checksum_sha256 = proof_checksum_sha256.to_s.strip.downcase.presence
  end

  # The current (non-superseded) version must always have a proof file attached.
  def proof_attached_for_current_version
    return unless current_version?
    return if proof.attached?

    errors.add(:proof, :blank)
  end
end
