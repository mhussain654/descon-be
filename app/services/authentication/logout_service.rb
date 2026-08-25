# frozen_string_literal: true

module Authentication
  class LogoutService < ApplicationService
    def initialize(session:, request_id:, ip_address:, user_agent:)
      @session = session
      @request_id = request_id
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      already_revoked = @session.revoked?
      @session.revoke!
      log_event unless already_revoked
      @session
    end

    private

    def log_event
      EventLogger.call(
        event_code: 'logout_succeeded',
        context: request_context,
        subject: { user: @session.user, session: @session },
        metadata: {}
      )
    end

    def request_context
      { request_id: @request_id, ip_address: @ip_address, user_agent: @user_agent }
    end
  end
end
