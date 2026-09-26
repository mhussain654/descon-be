# frozen_string_literal: true

module AiCalls
  module Prompts
    OutboundPromptContent = Struct.new(:dynamic_variables, :conversation_config_override, keyword_init: true)
  end
end
