# frozen_string_literal: true

module Users
  class SessionRevoker < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      @user.sessions.active.find_each(&:revoke!)
    end
  end
end
