# frozen_string_literal: true

# The single admin-editable row of feature switches, from the admin App
# Settings page. Each switch is the business on/off; the feature also needs its
# server setup (env vars, credentials), so it runs only when both are on. Same
# singleton shape as SupportSetting -- #current is the only supported way to
# obtain the row.
class AppFeatureSetting < ApplicationRecord
  SWITCHES = %i[
    card_payment voucher_payment progress_sms automatic_calls bulk_calls document_ocr document_identity_check
  ].freeze

  # KuickPay voucher dates: due date = issue date + due days; expiry = due date + grace days.
  VOUCHER_DUE_DAYS = (1..60)
  VOUCHER_GRACE_DAYS = (0..15)

  belongs_to :updated_by, class_name: 'User', optional: true

  validates :singleton_guard, inclusion: { in: [true] }
  validates(*SWITCHES.map { |switch| :"#{switch}_enabled" }, inclusion: { in: [true, false] })
  validates :voucher_due_days, numericality: { only_integer: true, in: VOUCHER_DUE_DAYS }
  validates :voucher_grace_days, numericality: { only_integer: true, in: VOUCHER_GRACE_DAYS }

  before_destroy :raise_readonly_record

  # Returns the singleton row, creating it (every switch on, except
  # document_identity_check, which rejects uploads and so starts off) on first access
  # anywhere. Race-safe: a concurrent first access loses the unique-index race
  # and simply reads back the winner's row instead.
  def self.current
    first || create!(singleton_guard: true)
  rescue ActiveRecord::RecordNotUnique
    first!
  end

  def self.enabled?(switch)
    raise ArgumentError, "unknown feature switch: #{switch}" unless SWITCHES.include?(switch.to_sym)

    current.public_send(:"#{switch}_enabled")
  end

  private

  def raise_readonly_record
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is a singleton and cannot be destroyed"
  end
end
