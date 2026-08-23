# frozen_string_literal: true

class Communication < ApplicationRecord
  CODE_FORMAT = /\A[a-z0-9_]+\z/
  DIRECTION_CODES = %w[inbound outbound].freeze
  LOCALES = %w[en ur].freeze

  belongs_to :candidate_assignment
  belongs_to :initiated_by, class_name: 'User', optional: true

  before_validation :assign_public_id, on: :create
  before_validation :normalize_codes

  validates :public_id, presence: true, uniqueness: true
  validates :channel_code, :direction_code, :status_code, presence: true, format: { with: CODE_FORMAT }
  validates :direction_code, inclusion: { in: DIRECTION_CODES }
  validates :locale, inclusion: { in: LOCALES }

  NORMALIZED_CODE_ATTRIBUTES = %i[channel_code direction_code status_code].freeze

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def normalize_codes
    NORMALIZED_CODE_ATTRIBUTES.each do |attribute|
      self[attribute] = self[attribute].to_s.strip.downcase
    end

    self.locale = locale.to_s.strip.downcase.presence || 'en'
    normalize_template_code
    normalize_provider_reference
    normalize_error_code
  end

  def normalize_template_code
    self.template_code = template_code.to_s.strip.downcase.presence
  end

  def normalize_provider_reference
    self.provider_reference = provider_reference.to_s.strip.presence
  end

  def normalize_error_code
    self.error_code = error_code.to_s.strip.downcase.presence
  end
end
