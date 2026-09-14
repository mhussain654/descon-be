# frozen_string_literal: true

module AiCalls
  # Redacts CNIC- and 6-digit-code-shaped spans from transcript text before
  # it's ever persisted -- a spoken CNIC (inbound verification) or a spoken
  # OTP carries the same "must never reach a persisted transcript" risk
  # (see the plan's "OTP must never reach a persisted transcript, event
  # payload, or log" and the CNIC-in-transcript note added 2026-09-11).
  # Best-effort, not a guarantee: DTMF entry is preferred over spoken
  # entry wherever the ElevenLabs/Twilio setup reliably supports it.
  module TranscriptRedactor
    CNIC_PATTERN = /\b\d{5}-\d{7}-\d\b|\b\d{13}\b/
    SIX_DIGIT_CODE_PATTERN = /\b\d{6}\b/

    def self.call(text)
      return text if text.blank?

      text.gsub(CNIC_PATTERN, '[redacted-cnic]').gsub(SIX_DIGIT_CODE_PATTERN, '[redacted-code]')
    end
  end
end
