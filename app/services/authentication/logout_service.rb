# frozen_string_literal: true

module Authentication
  class LogoutService < ApplicationService
    def initialize(session:)
      @session = session
    end

    def call
      @session.revoke!
    end
  end
end
