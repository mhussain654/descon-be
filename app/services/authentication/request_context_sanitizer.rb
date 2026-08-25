# frozen_string_literal: true

module Authentication
  class RequestContextSanitizer < ApplicationService
    MAX_USER_AGENT_LENGTH = 255
    MAX_IP_ADDRESS_LENGTH = 64

    def initialize(request_id:, user_agent:, ip_address:)
      @request_id = request_id.to_s
      @user_agent = user_agent
      @ip_address = ip_address
    end

    def call
      {
        request_id: @request_id,
        user_agent: sanitize_text(@user_agent, max_length: MAX_USER_AGENT_LENGTH),
        ip_address: sanitize_text(@ip_address, max_length: MAX_IP_ADDRESS_LENGTH)
      }
    end

    private

    def sanitize_text(value, max_length:)
      value.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').truncate(max_length)
    end
  end
end
