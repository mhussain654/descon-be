# frozen_string_literal: true

module AiCalls
  module Providers
    # Bundles the per-call content ElevenlabsAdapter#initiate_outbound_call needs
    # into one value object -- the individual fields are the caller's
    # (AiCalls::TriggerOutboundCallService) responsibility to assemble; this
    # adapter only knows the wire format they get sent in.
    OutboundCallRequest = Struct.new(
      :agent_id, :agent_phone_number_id, :to_number, :dynamic_variables,
      :conversation_config_override, :recording_enabled,
      keyword_init: true
    )
  end
end
