# frozen_string_literal: true

module Sms
  # Single entry point for sending an SMS -- application code (e.g.
  # CandidateAuthentication::Otp::RequestService) depends only on this
  # class, never on a specific vendor (AGENTS.md: "Isolate external systems
  # behind provider adapters. Application code must not directly depend on
  # SendPK... or other vendor-specific APIs"). Providers::TestProvider (no
  # network call) and Providers::SendpkProvider (the real vendor) both
  # satisfy the same #deliver(to:, variables:, template:, locale:, sender:) interface,
  # selected below by SMS_PROVIDER.
  #
  # No message text is passed: send.pk only sends its pre-approved templates
  # (free text is rejected), so the wording lives in send.pk, not in this app.
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
    # `variables` are the values for the vendor's pre-approved template;
    # `template` names the message (e.g. :otp, :registered), `locale` picks
    # its English or Urdu template and `sender` is the recipient's
    # Candidate#sms_sender (the brand name or the short code).
    def initialize(to:, variables:, template:, sender:, locale: 'en')
      @to = to
      @variables = variables
      @template = template
      @sender = sender
      @locale = locale
    end

    def call
      provider.deliver(to: @to, variables: @variables, template: @template, locale: @locale, sender: @sender)
    end

    private

    def provider
      case provider_name
      when 'test' then Providers::TestProvider.new
      when 'sendpk' then Providers::SendpkProvider.new
      else
        raise ProviderNotConfiguredError, "Unknown SMS_PROVIDER: #{provider_name.inspect}"
      end
    end

    def provider_name
      ENV.fetch('SMS_PROVIDER', 'test')
    end
  end
end
