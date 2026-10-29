# frozen_string_literal: true

module CandidateSms
  # Records one progress SMS for a candidate and queues it for sending. The
  # `dedupe_key` names the event the SMS is about (e.g. "qvc_appointment:<attempt
  # id>"), so asking twice for the same event sends it once. Meant to run inside
  # the caller's transaction: Solid Queue is DB-backed, so the job only exists if
  # that transaction commits. An inactive candidate gets nothing; a message
  # switched off in App Settings is recorded as skipped and not queued.
  class ScheduleDelivery < ApplicationService
    DATE_FORMAT = '%d-%m-%Y'

    def self.format_date(date) = date&.strftime(DATE_FORMAT)

    def self.locale_for(candidate)
      CandidateSmsDelivery::LOCALES.include?(candidate.preferred_locale) ? candidate.preferred_locale : 'en'
    end

    def initialize(assignment:, message_code:, dedupe_key:, variables: {})
      @assignment = assignment
      @message_code = message_code.to_s
      @dedupe_key = dedupe_key
      @variables = variables
    end

    def call
      raise ArgumentError, "unknown SMS message: #{@message_code}" unless known_message?

      candidate = @assignment.candidate
      return unless candidate.active?

      enabled = AppFeatureSetting.sms_message_enabled?(@message_code)
      delivery_id = insert_delivery(candidate, enabled:)
      DeliveryJob.perform_later(candidate_sms_delivery_id: delivery_id) if delivery_id && enabled
    end

    private

    def known_message? = CandidateSmsDelivery::MESSAGE_CODES.include?(@message_code)

    # ON CONFLICT DO NOTHING rather than a uniqueness rescue: a unique violation
    # would abort the caller's whole transaction (the stage change with it).
    def insert_delivery(candidate, enabled:)
      CandidateSmsDelivery.insert_all( # rubocop:disable Rails/SkipsModelValidations -- the row is built complete here
        [delivery_row(candidate).merge(status_attributes(enabled))], unique_by: :dedupe_key, returning: :id
      ).rows.flatten.first
    end

    # A message switched off in App Settings is recorded as skipped, never sent later.
    def status_attributes(enabled)
      enabled ? { status: 'pending' } : { status: 'skipped', error_code: 'disabled' }
    end

    def delivery_row(candidate)
      {
        public_id: SecureRandom.uuid, candidate_id: candidate.id, candidate_assignment_id: @assignment.id,
        message_code: @message_code, dedupe_key: @dedupe_key, locale: self.class.locale_for(candidate),
        variables: { name: candidate.full_name }.merge(@variables).transform_values(&:to_s)
      }
    end
  end
end
