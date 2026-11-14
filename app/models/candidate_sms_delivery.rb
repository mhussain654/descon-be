# frozen_string_literal: true

# One SMS to a candidate and whether it went out: a progress SMS queued
# automatically by CandidateSms::ScheduleDelivery, or one a staff member sent
# by hand (CandidateSms::SendManual, `sent_by` set). Sent by
# CandidateSms::DeliveryJob.
class CandidateSmsDelivery < ApplicationRecord
  MESSAGE_CODES = %w[
    registered documents_submitted document_rejected medical_appointment fee_pending medical_unfit qvc_appointment
    visa_issued visa_rejected protection_call ticket_and_flight_details ticket_handover flight_details
    medical_appointment_changed qvc_appointment_changed flight_details_changed
  ].freeze
  STATUSES = %w[pending sent failed skipped].freeze
  LOCALES = %w[en ur].freeze

  belongs_to :candidate
  belongs_to :candidate_assignment
  belongs_to :sent_by, class_name: 'User', optional: true

  before_validation :assign_public_id, on: :create

  validates :public_id, :dedupe_key, presence: true, uniqueness: true
  validates :message_code, inclusion: { in: MESSAGE_CODES }
  validates :status, inclusion: { in: STATUSES }
  validates :locale, inclusion: { in: LOCALES }

  def pending? = status == 'pending'
  def manual? = sent_by_id.present?

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end
