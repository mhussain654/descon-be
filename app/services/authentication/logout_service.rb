# frozen_string_literal: true

module Authentication
  class LogoutService < ApplicationService
    private attr_reader :request_context

    def initialize(session:, request_id:, ip_address:, user_agent:)
      @session = session
      @request_context = RequestContextSanitizer.call(request_id:, user_agent:, ip_address:)
    end

    def call
      revoked_by_this_call = false

      Session.transaction do
        @session.lock!
        revoked_by_this_call = !@session.revoked?
        @session.revoke!
      end

      log_event if revoked_by_this_call
      @session.reload
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
  end
end
