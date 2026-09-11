# frozen_string_literal: true

module AiCalls
  # Parses the ElevenLabs conversation-initiation webhook payload (fired
  # when an inbound call reaches our imported Twilio number, before the
  # conversation itself starts) into the fields this app needs.
  #
  # ASSUMED SHAPE -- based on ElevenLabs' documented Conversational AI
  # Twilio-integration webhook format (caller_id under a `caller_id` or
  # nested `twilio`-shaped key). Not yet verified against a real delivered
  # payload (no sandbox/production ElevenLabs credentials exist yet -- same
  # caveat as AiCalls::PostCallWebhookPayload). Confirm and adjust this
  # class, and only this class, once real payloads are available.
  class ConversationInitiationPayload
    def initialize(raw)
      @raw = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
    end

    def conversation_id
      data['conversation_id']
    end

    def caller_number
      data['caller_id'] || data.dig('twilio', 'caller') || data.dig('twilio', 'from')
    end

    private

    def data
      @raw['data'].is_a?(Hash) ? @raw['data'] : @raw
    end
  end
end
