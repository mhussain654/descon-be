# frozen_string_literal: true

module Api
  module V1
    class UsersController < ProtectedStaffController
      def index
        authorize User

        query = ::Users::IndexQuery.new(scope: policy_scope(User), params:)
        users = query.call

        render_payload(
          collection_payload(
            data: users.map { |user| ::Users::SummarySerializer.new(user).as_json },
            pagination: query.pagination
          )
        )
      end
    end
  end
end
