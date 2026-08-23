# frozen_string_literal: true

class Payment < ApplicationRecord
  CODE_FORMAT = /\A[a-z0-9_]+\z/
  CURRENCY_FORMAT = /\A[A-Z]{3}\z/

  belongs_to :candidate_assignment
  belongs_to :recorded_by, class_name: 'User', optional: true

  before_validation :assign_public_id, on: :create
  before_validation :normalize_codes

  validates :public_id, presence: true, uniqueness: true
  validates :payment_type_code, :status_code, presence: true, format: { with: CODE_FORMAT }
  validates :currency_code, presence: true, format: { with: CURRENCY_FORMAT }
  validates :amount, numericality: { greater_than: 0 }
  validates :external_reference, uniqueness: true, allow_blank: true

  NORMALIZED_CODE_ATTRIBUTES = %i[payment_type_code status_code].freeze

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def normalize_codes
    NORMALIZED_CODE_ATTRIBUTES.each do |attribute|
      self[attribute] = self[attribute].to_s.strip.downcase
    end

    self.currency_code = currency_code.to_s.strip.upcase
    self.external_reference = external_reference.to_s.strip.presence
  end
end
