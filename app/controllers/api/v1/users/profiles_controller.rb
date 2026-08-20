# frozen_string_literal: true

module Api
  module V1
    module Users
      class ProfilesController < BaseController
        before_action :authenticate_current_user!

        def show
          authorize current_user, :show?
          render_success(data: Users::ProfileSerializer.new(current_user).as_json)
        end
      end
    end
  end
end
