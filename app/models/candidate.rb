# frozen_string_literal: true

class Candidate < ApplicationRecord
  PREFERRED_LOCALES = %w[en ur].freeze
  SOURCE_CODES = %w[admin_ui csv_import].freeze
  STATUS_CODE_FORMAT = /\A[a-z0-9_]+\z/
  CNIC_FORMAT = /\A\d{5}-\d{7}-\d\z/
  MOBILE_NUMBER_FORMAT = /\A\+?\d{10,15}\z/
  PASSPORT_NUMBER_FORMAT = /\A[A-Z0-9-]+\z/

  belongs_to :created_by, class_name: 'User'

  has_many :candidate_assignments, dependent: :restrict_with_exception
  has_many :audit_events, dependent: :restrict_with_exception
  has_many :candidate_sessions, dependent: :destroy
  has_many :candidate_otp_challenges, dependent: :destroy

  before_validation :assign_public_id, on: :create
  before_validation :normalize_cnic
  before_validation :normalize_mobile_number
  before_validation :normalize_passport_number
  before_validation :normalize_status_code

  scope :active, -> { where(active: true) }

  validates :active, inclusion: { in: [true, false] }
  validates :public_id, presence: true, uniqueness: true
  validates :full_name, presence: true
  validates :cnic, presence: true, uniqueness: true, format: { with: CNIC_FORMAT }
  validates :mobile_number, presence: true, format: { with: MOBILE_NUMBER_FORMAT }
  validates :passport_number,
            uniqueness: true,
            allow_blank: true,
            format: { with: PASSPORT_NUMBER_FORMAT },
            if: :passport_number?
  validates :preferred_locale, inclusion: { in: PREFERRED_LOCALES }
  validates :source_code, inclusion: { in: SOURCE_CODES }
  validates :status_code, presence: true, format: { with: STATUS_CODE_FORMAT }

  def active_for_authentication? = active?

  def current_assignment
    candidate_assignments.order(created_at: :desc).first
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def normalize_cnic
    self.cnic = Candidates::CnicNormalizer.call(cnic)
  end

  def normalize_mobile_number
    raw_value = mobile_number.to_s.strip
    digits = raw_value.gsub(/\D/, '')
    return if digits.blank?

    self.mobile_number = raw_value.start_with?('+') ? "+#{digits}" : digits
  end

  def normalize_passport_number
    normalized_value = passport_number.to_s.upcase.gsub(/\s+/, '')
    self.passport_number = normalized_value.presence
  end

  def normalize_status_code
    self.status_code = status_code.to_s.strip.downcase.presence || 'registered'
  end
end
