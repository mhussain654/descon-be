# frozen_string_literal: true

# A person registered in the recruitment pipeline, identified by CNIC and mobile number, who
# progresses through one or more assignments toward overseas deployment.
class Candidate < ApplicationRecord
  PREFERRED_LOCALES = %w[en ur].freeze
  SOURCE_CODES = %w[admin_ui csv_import].freeze
  STATUS_CODE_FORMAT = /\A[a-z0-9_]+\z/
  CNIC_FORMAT = /\A\d{5}-\d{7}-\d\z/
  MOBILE_NUMBER_FORMAT = /\A\+?\d{10,15}\z/
  PASSPORT_NUMBER_FORMAT = /\A[A-Z0-9-]+\z/

  # Deterministic (not randomized) so the existing uniqueness validation and the OTP-login
  # lookup-by-CNIC (Candidate.active.find_by(cnic:)) keep working as equality queries (MPS-901).
  # Raw SQL string comparisons against these columns (as opposed to ActiveRecord's own
  # hash-condition `where`) would compare plaintext against ciphertext and silently match
  # nothing -- see Admin::Candidates::IndexQuery's search, rewritten for this reason.
  encrypts :cnic, deterministic: true
  encrypts :next_of_kin_cnic, deterministic: true
  encrypts :passport_number, deterministic: true

  belongs_to :created_by, class_name: 'User'

  has_many :candidate_assignments, dependent: :restrict_with_exception
  has_many :audit_events, dependent: :restrict_with_exception
  has_many :candidate_sessions, dependent: :destroy
  has_many :candidate_otp_challenges, dependent: :destroy
  has_many :candidate_consents, dependent: :restrict_with_exception
  has_many :candidate_ai_calls, dependent: :restrict_with_exception

  before_validation :assign_public_id, on: :create
  before_validation :normalize_cnic
  before_validation :normalize_mobile_number
  before_validation :normalize_next_of_kin_mobile_number
  before_validation :normalize_next_of_kin_cnic
  before_validation :normalize_passport_number
  before_validation :normalize_status_code

  scope :active, -> { where(active: true) }

  validates :active, inclusion: { in: [true, false] }
  validates :public_id, presence: true, uniqueness: true
  validates :full_name, presence: true
  validates :cnic, presence: true, uniqueness: true, format: { with: CNIC_FORMAT }
  # No DB-level unique index yet -- the existing dev/test data already has a
  # collision, so adding one needs a data-cleanup migration step that is a
  # separate, deliberate decision, not something to bundle into this
  # duplicate-mobile-number validation. Tracked as a known follow-up.
  # rubocop:disable Rails/UniqueValidationWithoutIndex
  validates :mobile_number, presence: true, uniqueness: true, format: { with: MOBILE_NUMBER_FORMAT }
  # rubocop:enable Rails/UniqueValidationWithoutIndex
  validates :next_of_kin_mobile_number, format: { with: MOBILE_NUMBER_FORMAT }, allow_blank: true
  validates :next_of_kin_cnic, format: { with: CNIC_FORMAT }, allow_blank: true
  validates :passport_number,
            uniqueness: true,
            allow_blank: true,
            format: { with: PASSPORT_NUMBER_FORMAT },
            if: :passport_number?
  validates :preferred_locale, inclusion: { in: PREFERRED_LOCALES }
  validates :source_code, inclusion: { in: SOURCE_CODES }
  validates :status_code, presence: true, format: { with: STATUS_CODE_FORMAT }
  validate :next_of_kin_fields_are_complete

  # Whether Devise/Warden should treat this candidate as allowed to authenticate.
  def active_for_authentication? = active?

  # The candidate's most recently created assignment (uses the loaded association in memory
  # when available to avoid an extra query, otherwise queries for the newest row).
  def current_assignment
    if association(:candidate_assignments).loaded?
      return candidate_assignments.max_by { |assignment| [assignment.created_at, assignment.id] }
    end

    candidate_assignments.order(created_at: :desc, id: :desc).first
  end

  private

  # Assigns a public-facing UUID identifier on creation, if one isn't already set.
  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  # Normalizes the CNIC into the canonical hyphenated format via the shared normalizer.
  def normalize_cnic
    self.cnic = Candidates::CnicNormalizer.call(cnic)
  end

  # Strips whitespace and keeps only digits (plus a leading '+' if present) in the mobile number.
  def normalize_mobile_number
    raw_value = mobile_number.to_s.strip
    digits = raw_value.gsub(/\D/, '')
    return if digits.blank?

    self.mobile_number = raw_value.start_with?('+') ? "+#{digits}" : digits
  end

  # Uppercases the passport number and removes internal whitespace, blanking it out if empty.
  def normalize_passport_number
    normalized_value = passport_number.to_s.upcase.gsub(/\s+/, '')
    self.passport_number = normalized_value.presence
  end

  # Strips whitespace and keeps only digits (plus a leading '+' if present) in the next of kin's mobile number.
  def normalize_next_of_kin_mobile_number
    raw_value = next_of_kin_mobile_number.to_s.strip
    digits = raw_value.gsub(/\D/, '')
    self.next_of_kin_mobile_number = raw_value.start_with?('+') ? "+#{digits}" : digits.presence
  end

  # Normalizes the next of kin's CNIC into the canonical hyphenated format via the shared normalizer.
  def normalize_next_of_kin_cnic
    self.next_of_kin_cnic = Candidates::CnicNormalizer.call(next_of_kin_cnic).presence
  end

  # Next of kin details must be given either all together or not at all; flags whichever fields are missing.
  def next_of_kin_fields_are_complete
    next_of_kin_fields = %i[next_of_kin_name next_of_kin_relationship next_of_kin_mobile_number next_of_kin_cnic]
    return if next_of_kin_fields.all? { |field| public_send(field).blank? }
    return if next_of_kin_fields.all? { |field| public_send(field).present? }

    next_of_kin_fields.each { |field| errors.add(field, :blank) if public_send(field).blank? }
  end

  # Trims and lowercases the status code, defaulting to 'registered' when blank.
  def normalize_status_code
    self.status_code = status_code.to_s.strip.downcase.presence || 'registered'
  end
end
