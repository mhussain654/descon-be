# frozen_string_literal: true

module Users
  class ProfileSerializer
    def initialize(user)
      @user = user
    end

    def as_json(*)
      {
        id: @user.public_id,
        email: @user.email,
        role: @user.role,
        permissions: @user.effective_permission_codes,
        selected_campaign: @user.selected_campaign && ::Admin::CampaignSerializer.new(@user.selected_campaign).as_json
      }
    end
  end
end
