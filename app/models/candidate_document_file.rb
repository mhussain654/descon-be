# frozen_string_literal: true

# One physical file of a CandidateDocument -- e.g. passport page 1, the back
# of a CNIC, or one of several certificates. The document owns the single
# review status and version history; its files are fixed once uploaded (a
# replacement creates a new document version with a new file set).
class CandidateDocumentFile < ApplicationRecord
  # `combined` is one PDF holding every part; the paired codes label image
  # parts; `certificate` may repeat (several certificates under one item).
  SIDE_CODES = %w[combined front back page_1 page_2 certificate].freeze
  REPEATABLE_SIDE_CODES = %w[certificate].freeze
  # Parts that must be uploaded together when either one is used.
  SIDE_PAIRS = [%w[front back], %w[page_1 page_2]].freeze
  # Which part best represents the whole document (OCR, legacy single-file
  # fields): a combined PDF, else the first page/front.
  PRIMARY_SIDE_PRIORITY = %w[combined page_1 front].freeze

  belongs_to :candidate_document, inverse_of: :files

  has_one_attached :file

  before_validation :assign_public_id, on: :create
  before_validation :normalize_checksum

  validates :public_id, presence: true, uniqueness: true
  validates :position, numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :candidate_document_id }
  validates :side_code, inclusion: { in: SIDE_CODES }, allow_nil: true
  validates :original_filename, :content_type, :checksum_sha256, presence: true
  validates :byte_size, numericality: { greater_than: 0 }
  validate :file_attached

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def normalize_checksum
    self.checksum_sha256 = checksum_sha256.to_s.strip.downcase.presence
  end

  def file_attached
    errors.add(:file, :blank) unless file.attached?
  end
end
