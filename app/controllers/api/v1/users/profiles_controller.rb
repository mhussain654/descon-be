# frozen_string_literal: true

module Api
  module V1
    module Users
      # Lets an authenticated staff user view their own profile and choose
      # their working campaign.
      class ProfilesController < ProtectedStaffController
        # Returns the current staff user's own profile details.
        def show
          authorize current_user, :show?
          render_success(data: ::Users::ProfileSerializer.new(current_user).as_json)
        end

        # Sets the working campaign (`selected_campaign_id`: a campaign id, or null for
        # all campaigns). Every candidate list, dashboard and report follows it.
        def update
          authorize current_user, :update_profile?

          current_user.update!(selected_campaign: selected_campaign)
          render_success(data: ::Users::ProfileSerializer.new(current_user).as_json)
        end

        private

        def selected_campaign
          campaign_id = params.expect(profile: [:selected_campaign_id])[:selected_campaign_id].presence
          return if campaign_id.nil?

          ::Campaign.active.find_by(public_id: campaign_id) ||
            raise(ValidationError.new(field: 'profile.selected_campaign_id',
                                      message: I18n.t('api.errors.unknown_campaign')))
        end
      end
    end
  end
end
