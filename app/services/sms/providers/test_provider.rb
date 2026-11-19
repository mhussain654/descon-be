# frozen_string_literal: true

module Sms
  module Providers
    # Development/test-only provider -- no network call, no credentials.
    # Deterministically fails delivery for numbers matching
    # UNDELIVERABLE_NUMBER_PATTERN so both success and failure paths are
    # exercisable without a real SMS vendor (see MPS-106's reserved demo
    # candidate). Logs only the message's name and a masked number, never its
    # values (which may contain an OTP).
    class TestProvider
      UNDELIVERABLE_NUMBER_PATTERN = /0{10,}\z/

      def deliver(to:, template:, **)
        Rails.logger.info("[Sms::Providers::TestProvider] delivering #{template} message to #{mask(to)}")

        if to.to_s.match?(UNDELIVERABLE_NUMBER_PATTERN)
          return DeliveryResult.new(success: false, error_code: 'undeliverable')
        end

        DeliveryResult.new(success: true, provider_reference: SecureRandom.uuid)
      end

      private

      def mask(destination)
        digits = destination.to_s
        return digits if digits.length <= 4

        "#{'*' * (digits.length - 4)}#{digits.last(4)}"
      end
    end
  end
end
