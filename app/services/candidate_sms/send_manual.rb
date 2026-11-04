# frozen_string_literal: true

module CandidateSms
  # Sends one SMS a staff member picked by hand from the candidate page: any
  # message with a template id for the chosen language, whether or not it is
  # sent automatically, and never the login code. The staff member fills the
  # values the template uses. The SMS is recorded as a CandidateSmsDelivery
  # (sent_by set) and sent by DeliveryJob like an automatic one.
  class SendManual < ApplicationService
    def initialize(candidate:, actor:, message_code:, locale:, variables:)
      @candidate = candidate
      @actor = actor
      @message_code = message_code.to_s
      @locale = locale.to_s
      @variables = variables.to_h.transform_keys(&:to_s)
    end

    def call
      template = sendable_template!
      assignment = current_assignment!
      delivery = CandidateSmsDelivery.create!(
        candidate: @candidate, candidate_assignment: assignment, sent_by: @actor, message_code: @message_code,
        locale: @locale, variables: values_for!(template), dedupe_key: "manual:#{SecureRandom.uuid}", status: 'pending'
      )
      DeliveryJob.perform_later(candidate_sms_delivery_id: delivery.id)
      delivery
    end

    # The messages staff can send: every one except the login code, with a template id in at least one language.
    def self.sendable_templates
      SmsTemplate.where.not(message_code: 'otp')
                 .where('template_id_en IS NOT NULL OR template_id_ur IS NOT NULL')
                 .sort_by { |template| SmsTemplate::MESSAGE_CODES.index(template.message_code) }
    end

    private

    def sendable_template!
      template = SmsTemplate.find_for(@message_code) unless @message_code == 'otp'
      raise invalid('sms_message_unavailable', 'sms_message.message_code') if template.blank?
      unless CandidateSmsDelivery::LOCALES.include?(@locale) && template.template_id_for(@locale).present?
        raise invalid('sms_language_unavailable', 'sms_message.locale')
      end

      template
    end

    def current_assignment!
      raise invalid('sms_candidate_inactive', 'sms_message') unless @candidate.active?

      @candidate.current_assignment || raise(invalid('sms_no_current_assignment', 'sms_message'))
    end

    def values_for!(template)
      template.variables.index_with { |name| @variables[name].to_s.strip }.tap do |values|
        missing = values.find { |_, value| value.blank? }&.first
        raise invalid('sms_value_required', "sms_message.variables.#{missing}") if missing
      end
    end

    def invalid(key, field) = ValidationError.new(message: I18n.t("api.errors.#{key}"), field:)
  end
end
