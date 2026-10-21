# frozen_string_literal: true

module AiCalls
  # RoboCall.pk settings: the api key from the encrypted credentials (like
  # SendPK's), the rest from ENV. Kept apart from AiCalls::Configuration so
  # that class stays about the provider-independent calling controls.
  #   robocall:
  #     production:
  #       api_key: ...
  class RobocallConfiguration
    def api_key
      Rails.application.credentials.dig(:robocall, Rails.env.to_sym, :api_key).to_s.strip.presence
    end

    def base_url
      ENV.fetch('ROBOCALL_BASE_URL', 'https://portal.robocall.pk').strip
    end

    # How long after a call was placed RoboCall's own automatic retries (Call
    # Settings: retry delay and count) may still turn a "no answer" into an
    # answered call. A not-answered status is only final after this window;
    # set it to (retry delay x number of retries) plus a few minutes.
    def retry_window_minutes
      ENV.fetch('ROBOCALL_RETRY_WINDOW_MINUTES', 30).to_i
    end

    # The most candidates one bulk call may include. This is our own ceiling,
    # kept at what RoboCall can take in one run; the admin page shows it too.
    def bulk_batch_limit
      ENV.fetch('ROBOCALL_BULK_BATCH_LIMIT', 200).to_i
    end

    # Pause between two calls of one bulk batch, so a few hundred requests do
    # not hit RoboCall at once (no rate limit is documented).
    def bulk_call_spacing_seconds
      ENV.fetch('ROBOCALL_BULK_CALL_SPACING_SECONDS', 2).to_i
    end

    def open_timeout
      ENV.fetch('ROBOCALL_OPEN_TIMEOUT_SECONDS', 5).to_i
    end

    def read_timeout
      ENV.fetch('ROBOCALL_READ_TIMEOUT_SECONDS', 10).to_i
    end
  end
end
