# frozen_string_literal: true

module Sms
  # Single entry point for sending an SMS -- application code (e.g.
  # CandidateAuthentication::Otp::RequestService) depends only on this
  # class, never on a specific vendor (AGENTS.md: "Isolate external systems
  # behind provider adapters. Application code must not directly depend on
  # SendPK... or other vendor-specific APIs"). No real vendor is integrated
  # yet -- this is the first provider adapter in the codebase, added by
  # MPS-201 to send the OTP; a real SendPK (or other) implementation is a
  # second class satisfying the same #deliver(to:, body:) interface as
  # Sms::Providers::TestProvider, selected below by SMS_PROVIDER.
  #
  # Deliberately called synchronously (not via ActiveJob) from the request
  # path: the raw OTP code only exists in the caller's local scope for the
  # brief window between generation and this call, and Solid Queue persists
  # job arguments in its own database table until the job completes --
  # putting the raw code through that queue would mean writing an
  # unencrypted, un-audited copy of a "hashed at rest, never logged" secret
  # to disk (AGENTS.md: "Do not place secrets or unnecessary personal data
  # in job arguments" / ticket: "OTP is never returned in any API response
  # or log"). SMS providers typically respond in well under a second, which
  # is an acceptable synchronous wait during an OTP request the candidate is
  # already expecting to take a moment.
  class SendMessage < ApplicationService
    def initialize(to:, body:)
      @to = to
      @body = body
    end

    def call
      provider.deliver(to: @to, body: @body)
    end

    private

    def provider
      case provider_name
      when 'test' then Providers::TestProvider.new
      else
        raise ProviderNotConfiguredError, "Unknown SMS_PROVIDER: #{provider_name.inspect}"
      end
    end

    def provider_name
      ENV.fetch('SMS_PROVIDER', 'test')
    end
  end
end
