# frozen_string_literal: true

module Authentication
  class EventLogger < ApplicationService
    def initialize(event_code:, context:, subject: {}, metadata: {})
      @event_code = event_code
      @context = context
      @subject = subject
      @metadata = metadata
    end

    def call
      AuthenticationEvent.create!(attributes)
    end

    private

    def attributes
      request_context.merge(
        event_code: @event_code,
        user: @subject[:user],
        session: @subject[:session],
        identifier_masked: masked_identifier,
        metadata: @metadata,
        occurred_at: Time.current
      )
    end

    def request_context
      @context.slice(:request_id, :ip_address, :user_agent).symbolize_keys
    end

    def masked_identifier
      mask_identifier(@subject[:identifier])
    end

    def mask_identifier(identifier)
      value = identifier.to_s.strip.downcase
      return if value.blank?

      local_part, domain = value.split('@', 2)
      return '***' if domain.blank?

      if local_part.length <= 2
        "#{local_part[0]}*@#{domain}"
      else
        "#{local_part[0]}#{'*' * (local_part.length - 2)}#{local_part[-1]}@#{domain}"
      end
    end
  end
end
