# frozen_string_literal: true

module Users
  class SummarySerializer
    def initialize(user)
      @user = user
    end

    def as_json(*)
      {
        id: @user.public_id,
        email: @user.email,
        role: @user.role,
        active: @user.active,
        created_at: @user.created_at.utc.iso8601
      }
    end
  end
end
