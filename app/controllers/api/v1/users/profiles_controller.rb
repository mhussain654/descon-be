# frozen_string_literal: true

module Api
  module V1
    module Users
      # Lets an authenticated staff user view their own profile.
      class ProfilesController < ProtectedStaffController
        # Returns the current staff user's own profile details.
        def show
          authorize current_user, :show?
          render_success(data: ::Users::ProfileSerializer.new(current_user).as_json)
        end
      end
    end
  end
end
