# frozen_string_literal: true

class Payment < ApplicationRecord
  CODE_FORMAT = /\A[a-z0-9_]+\z/
  CURRENCY_FORMAT = /\A[A-Z]{3}\z/
  STATUS_CODES = %w[checkout_pending paid failed cancelled].freeze
  NORMALIZED_CODE_ATTRIBUTES = %i[payment_type_code status_code provider_code].freeze
  STRIPPED_STRING_ATTRIBUTES = %i[
    external_reference
    provider_order_id
    provider_session_id
    provider_transaction_id
    provider_status_code
    provider_response_code
    checkout_url
  ].freeze

  belongs_to :candidate_assignment
  belongs_to :recorded_by, class_name: 'User', optional: true
  has_many :payment_events, dependent: :restrict_with_exception
  has_many :payment_reconciliation_findings, dependent: :restrict_with_exception

  before_validation :assign_public_id, on: :create
  before_validation :normalize_codes

  validates :public_id, presence: true, uniqueness: true
  validates :payment_type_code, :status_code, presence: true, format: { with: CODE_FORMAT }
  validates :currency_code, presence: true, format: { with: CURRENCY_FORMAT }
  validates :amount, numericality: { greater_than: 0 }
  validates :external_reference, uniqueness: true, allow_blank: true
  validates :provider_code, format: { with: CODE_FORMAT }, allow_blank: true
  validates :provider_order_id, :provider_session_id, uniqueness: true, allow_blank: true
  validates :status_code, inclusion: { in: STATUS_CODES }

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  def paid? = status_code == 'paid'

  def checkout_pending? = status_code == 'checkout_pending'

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def normalize_codes
    normalize_code_attributes
    self.currency_code = currency_code.to_s.strip.upcase
    normalize_string_attributes
  end

  def normalize_code_attributes
    NORMALIZED_CODE_ATTRIBUTES.each do |attribute|
      self[attribute] = self[attribute].to_s.strip.downcase
    end
  end

  def normalize_string_attributes
    STRIPPED_STRING_ATTRIBUTES.each do |attribute|
      self[attribute] = self[attribute].to_s.strip.presence
    end
  end
end
