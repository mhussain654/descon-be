# frozen_string_literal: true

# One send.pk message (the OTP or a progress SMS): the ids of its English and
# Urdu templates, approved in send.pk's dashboard, and whether it is sent
# automatically when the candidate reaches its stage (`enabled`). Any message
# with a template id can also be sent by hand from the candidate page,
# whether or not it is sent automatically (CandidateSms::SendManual).
# Edited by developers in App Settings; read by Sms::Configuration and
# CandidateSms::ScheduleDelivery. The set of messages is fixed in code
# (MESSAGE_CODES), so rows are edited, never added or removed.
class SmsTemplate < ApplicationRecord
  MESSAGE_CODES = (['otp'] + CandidateSmsDelivery::MESSAGE_CODES).freeze
  # Turning the OTP off would lock every candidate out of the app.
  ALWAYS_ENABLED = %w[otp].freeze
  # The values each message sends to its template, which must use these names.
  # A message not listed sends only the candidate's `name`. The client's
  # approved templates for registered, fee_pending, qvc_appointment,
  # ticket_and_flight_details and ticket_handover are fixed text, so they send
  # no values.
  VARIABLES = {
    'otp' => %w[code minutes],
    'registered' => [],
    'documents_submitted' => [],
    'visa_issued' => %w[country],
    'ticket_and_flight_details' => [],
    'ticket_handover' => [],
    'document_rejected' => %w[name document],
    'medical_appointment' => %w[name date],
    'fee_pending' => [],
    'qvc_appointment' => [],
    'protection_call' => %w[name date],
    'flight_details' => %w[name airline flight sector date time],
    'medical_appointment_changed' => %w[name date],
    'qvc_appointment_changed' => %w[name date],
    'flight_details_changed' => %w[name date time]
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

  def self.variables_for(message_code) = VARIABLES.fetch(message_code.to_s, %w[name])

  # The template id set for a locale ('en' or 'ur'), or nil.
  def template_id_for(locale) = locale.to_s == 'ur' ? template_id_ur : template_id_en

  def always_enabled? = ALWAYS_ENABLED.include?(message_code)
  def variables = self.class.variables_for(message_code)

  private

  def normalize_template_ids
    self.template_id_en = template_id_en.to_s.strip.presence
    self.template_id_ur = template_id_ur.to_s.strip.presence
  end
end
