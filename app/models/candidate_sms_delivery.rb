# frozen_string_literal: true

# One progress SMS to a candidate and whether it went out. Created by
# CandidateSms::ScheduleDelivery and sent by CandidateSms::DeliveryJob.
class CandidateSmsDelivery < ApplicationRecord
  MESSAGE_CODES = %w[
    registered document_rejected medical_appointment fee_pending medical_unfit qvc_appointment
    visa_issued visa_rejected protection_call ticket_handover flight_details
  ].freeze
  STATUSES = %w[pending sent failed skipped].freeze
  LOCALES = %w[en ur].freeze

  belongs_to :candidate
  belongs_to :candidate_assignment

  before_validation :assign_public_id, on: :create

  validates :public_id, :dedupe_key, presence: true, uniqueness: true
  validates :message_code, inclusion: { in: MESSAGE_CODES }
  validates :status, inclusion: { in: STATUSES }
  validates :locale, inclusion: { in: LOCALES }

  def pending? = status == 'pending'

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end
end
