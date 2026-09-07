# frozen_string_literal: true

module CandidateDocuments
  # Concern mixed into candidate document models to handle Police Character Certificate (PCC)
  # documents: auto-calculates the expiry date, exposes compliance status, and adds scopes for
  # finding expiring/expired/current PCC documents.
  module PoliceCharacterCompliance
    extend ActiveSupport::Concern

    PCC_REQUIREMENT_CODE = 'police_character'

    included do
      before_validation :apply_pcc_dates

      scope :police_character, -> { joins(:document_type).where(document_types: { code: PCC_REQUIREMENT_CODE }) }
      scope :pcc_expiring_between, ->(from, to) { police_character.where(expires_on: from..to) }
      scope :expired_pcc, ->(on: application_date) { police_character.where(arel_table[:expires_on].lt(on)) }
      scope :near_expiry_pcc, lambda { |on: application_date, warning_days: pcc_near_expiry_days|
        police_character.where(expires_on: on..(on + warning_days.days))
      }
      scope :current_pcc, lambda { |on: application_date, warning_days: pcc_near_expiry_days|
        police_character.where(arel_table[:expires_on].gt(on + warning_days.days))
      }

      validate :pcc_date_consistency
    end

    class_methods do
      # The current business date used as the reference point for PCC expiry comparisons.
      def application_date
        Time.zone.today
      end

      # The configurable warning window, in days, before a PCC is treated as "near expiry",
      # read from the PCC_NEAR_EXPIRY_DAYS environment variable (defaults to 30).
      def pcc_near_expiry_days
        value = Integer(ENV.fetch('PCC_NEAR_EXPIRY_DAYS', 30), exception: false)
        raise ArgumentError, 'PCC_NEAR_EXPIRY_DAYS must be a non-negative integer' if value.nil? || value.negative?

        value
      end
    end

    # Classifies this PCC document as 'expired', 'near_expiry', or 'current' relative to the
    # given date (or nil if it has no expiry date on record).
    def compliance_status(on: self.class.application_date)
      return if expires_on.blank?
      return 'expired' if expires_on < on
      return 'near_expiry' if expires_on <= on + self.class.pcc_near_expiry_days.days

      'current'
    end

    # True if this document's type is the Police Character Certificate.
    def police_character?
      document_type&.code == PCC_REQUIREMENT_CODE
    end

    private

    # Callback: for PCC documents with an issue date, sets the expiry date to six months later.
    def apply_pcc_dates
      return unless police_character?
      return if issued_on.blank?

      self.expires_on = issued_on.advance(months: 6)
    end

    # Callback: runs the PCC-specific issue/expiry date validations, but only for PCC documents.
    def pcc_date_consistency
      return unless police_character?

      validate_pcc_issue_date
      validate_pcc_expiry_date if issued_on.present?
    end

    # Requires the PCC issue date to be present and not in the future.
    def validate_pcc_issue_date
      errors.add(:issued_on, :blank) if issued_on.blank?
      return if issued_on.blank?

      errors.add(:issued_on, :invalid) if issued_on > self.class.application_date
    end

    # Requires the PCC expiry date to be exactly six months after the issue date.
    def validate_pcc_expiry_date
      return if expires_on == issued_on.advance(months: 6)

      errors.add(:expires_on, :invalid)
    end
  end
end
