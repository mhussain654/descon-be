# frozen_string_literal: true

module CandidateAuthentication
  module Otp
    # Lets a developer send a candidate a new sign-in code from the candidate
    # page, in English or Urdu, when the candidate's own code arrived late or
    # expired. It skips the app's resend cooldown and, like any new code,
    # replaces the candidate's earlier one.
    #
    # The plain code is returned to the caller once, so the developer can read
    # it out to the candidate -- a deliberate, client-approved exception to
    # "never returned in any API response", limited to the developer-only
    # `send_candidate_otp` permission. It is still stored only as a bcrypt
    # digest, never logged, and never shown again; the send itself is audited
    # (without the code).
    class StaffSendService < ApplicationService
      LOCALES = %w[en ur].freeze

      def initialize(candidate:, actor:, locale:, request_id:)
        @candidate = candidate
        @actor = actor
        @locale = locale.to_s
        @request_id = request_id
      end

      def call
        validate!
        payload = create_challenge!
        result = deliver(payload.fetch(:code))
        { challenge: payload.fetch(:challenge), code: payload.fetch(:code), sms_sent: result.success?,
          sms_error_code: result.error_code }
      end

      private

      def validate!
        raise ValidationError.new(field: 'otp.locale', message: I18n.t('api.errors.otp_locale_invalid')) unless
          LOCALES.include?(@locale)
        raise ValidationError.new(message: I18n.t('api.errors.otp_candidate_inactive')) unless @candidate.active?
        return unless StoreReview::Account.candidate?(@candidate)

        raise ValidationError.new(message: I18n.t('api.errors.otp_store_review_account'))
      end

      # Same per-CNIC lock as the app's own request, so the two never interleave.
      # No requested IP: the developer's own address is not the candidate's.
      def create_challenge!
        ActiveRecord::Base.transaction do
          Database::AdvisoryTransactionLock.call(scope: RequestService::LOCK_SCOPE, key: @candidate.cnic)
          CandidateOtpChallenge.generate_for(candidate: @candidate, sent_by: @actor)
                               .tap { |payload| audit!(payload.fetch(:challenge)) }
        end
      end

      def deliver(code)
        result = Sms::SendMessage.call(to: @candidate.mobile_number, variables: { code:, minutes: expiry_minutes },
                                       template: :otp, sender: @candidate.sms_sender, locale: @locale)
        log_failure(result.error_code) unless result.success?
        result
      rescue StandardError => e
        # The code is already saved, so the developer still gets it to read out.
        log_failure(e.class.name)
        Sms::DeliveryResult.new(success: false, error_code: 'delivery_error')
      end

      def log_failure(error_code)
        Rails.logger.warn({ event: 'staff_otp_delivery_failed', candidate_id: @candidate.id, error_code: }.to_json)
      end

      def audit!(challenge)
        AuditEvent.create!(
          actor: @actor, candidate: @candidate, entity_type: 'CandidateOtpChallenge', entity_id: challenge.id,
          action_code: 'candidate_otp_sent_by_staff', request_id: @request_id,
          metadata: { candidate_public_id: @candidate.public_id, locale: @locale, sms_sender: @candidate.sms_sender },
          occurred_at: Time.current
        )
      end

      def expiry_minutes = (CandidateOtpChallenge::EXPIRY_WINDOW / 1.minute).round
    end
  end
end
