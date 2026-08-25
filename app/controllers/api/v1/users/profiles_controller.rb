# frozen_string_literal: true

module Api
  module V1
    module Users
      class ProfilesController < ProtectedStaffController
        def show
          authorize current_user, :show?
          render_success(data: ::Users::ProfileSerializer.new(current_user).as_json)
        end
      end
    end
  end
end
