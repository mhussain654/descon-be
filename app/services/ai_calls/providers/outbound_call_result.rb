# frozen_string_literal: true

module AiCalls
  module Providers
    OutboundCallResult = Struct.new(:conversation_id, :twilio_call_sid, keyword_init: true)
  end
end
