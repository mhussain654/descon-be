# frozen_string_literal: true

# The single admin-editable row of feature switches, from the admin App
# Settings page. Each switch is the business on/off; the feature also needs its
# server setup (env vars, credentials), so it runs only when both are on. Same
# singleton shape as SupportSetting -- #current is the only supported way to
# obtain the row.
class AppFeatureSetting < ApplicationRecord
  SWITCHES = %i[
    card_payment voucher_payment progress_sms automatic_calls bulk_calls document_ocr
  ].freeze

  belongs_to :updated_by, class_name: 'User', optional: true

  validates :singleton_guard, inclusion: { in: [true] }
  validates(*SWITCHES.map { |switch| :"#{switch}_enabled" }, inclusion: { in: [true, false] })
  validate :disabled_sms_messages_known

  before_destroy :raise_readonly_record

  # Returns the singleton row, creating it (every switch on) on first access
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

  # A progress SMS goes out only while progress SMS are on and that message is not switched off.
  def self.sms_message_enabled?(message_code)
    setting = current
    setting.progress_sms_enabled && setting.disabled_sms_messages.exclude?(message_code.to_s)
  end

  private

  def disabled_sms_messages_known
    unknown = Array(disabled_sms_messages) - CandidateSmsDelivery::MESSAGE_CODES
    errors.add(:disabled_sms_messages, :inclusion) if unknown.any?
  end

  def raise_readonly_record
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is a singleton and cannot be destroyed"
  end
end
