# frozen_string_literal: true

# One send.pk message (the OTP or a progress SMS): the ids of its English and
# Urdu templates, approved in send.pk's dashboard, and whether it is sent.
# Edited by developers in App Settings; read by Sms::Configuration and
# CandidateSms::ScheduleDelivery. The set of messages is fixed in code
# (MESSAGE_CODES), so rows are edited, never added or removed.
class SmsTemplate < ApplicationRecord
  MESSAGE_CODES = (['otp'] + CandidateSmsDelivery::MESSAGE_CODES).freeze
  # Turning the OTP off would lock every candidate out of the app.
  ALWAYS_ENABLED = %w[otp].freeze
  # The values each message sends to its template, which must use these names.
  # Every progress SMS also sends the candidate's `name`.
  VARIABLES = {
    'otp' => %w[code minutes],
    'document_rejected' => %w[name document],
    'medical_appointment' => %w[name date],
    'fee_pending' => %w[name amount],
    'qvc_appointment' => %w[name date],
    'protection_call' => %w[name date],
    'ticket_handover' => %w[name date],
    'flight_details' => %w[name airline flight sector date time]
  }.freeze
  TEMPLATE_ID_FORMAT = /\A[0-9]{1,20}\z/

  belongs_to :updated_by, class_name: 'User', optional: true

  before_validation :normalize_template_ids

  validates :message_code, inclusion: { in: MESSAGE_CODES }, uniqueness: true
  validates :template_id_en, :template_id_ur, format: { with: TEMPLATE_ID_FORMAT }, allow_nil: true
  validates :enabled, inclusion: { in: [true, false] }
  validates :enabled, inclusion: { in: [true] }, if: :always_enabled?

  # A message without a row has nothing set up yet; it is not switched off.
  def self.enabled?(message_code)
    !exists?(message_code: message_code.to_s, enabled: false)
  end

  def self.find_for(message_code)
    find_by(message_code: message_code.to_s)
  end

  def always_enabled? = ALWAYS_ENABLED.include?(message_code)
  def variables = VARIABLES.fetch(message_code, %w[name])

  private

  def normalize_template_ids
    self.template_id_en = template_id_en.to_s.strip.presence
    self.template_id_ur = template_id_ur.to_s.strip.presence
  end
end
