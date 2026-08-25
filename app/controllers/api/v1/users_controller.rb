# frozen_string_literal: true

module Api
  module V1
    class UsersController < ProtectedStaffController
      def index
        authorize User

        query = ::Users::IndexQuery.new(scope: policy_scope(User), params:)
        users = query.call

        render_payload(collection_payload(data: serialized_users(users), pagination: query.pagination))
      end

      def create
        authorize User
        render_idempotent_response(scope: 'users.create', subject: current_user) { create_payload }
      end

      def update
        authorize target_user, :update?
        render_success(data: update_payload)
      end

      private

      def create_payload
        user = ::Users::CreateService.call(
          actor: current_user,
          attributes: create_user_attributes,
          request_id: request.request_id
        )

        success_payload(
          data: { user: serialized_user(user), message: t('api.users.invitation_created') },
          status: :created
        )
      end

      def update_payload
        updated_user = ::Users::UpdateService.call(
          actor: current_user,
          user: target_user,
          attributes: update_user_attributes,
          request_id: request.request_id
        )
        { user: serialized_user(updated_user), message: t('api.users.updated') }
      end

      def create_user_attributes
        enforce_allowed_keys!(params[:user], allowed_keys: %w[email role], prefix: 'user')
        create_params.to_h.symbolize_keys
      end

      def update_user_attributes
        enforce_allowed_keys!(params[:user], allowed_keys: %w[role staff_state], prefix: 'user')
        update_params.to_h.symbolize_keys
      end

      def create_params
        params.expect(user: %i[email role])
      end

      def update_params
        params.expect(user: %i[role staff_state])
      end

      def target_user
        @target_user ||= policy_scope(User).find_by!(public_id: params.expect(:id))
      end

      def serialized_user(user)
        ::Users::SummarySerializer.new(user).as_json
      end

      def serialized_users(users)
        users.map { |user| serialized_user(user) }
      end

      def enforce_allowed_keys!(parameter_object, allowed_keys:, prefix:)
        raw_parameters = parameter_object.respond_to?(:to_unsafe_h) ? parameter_object.to_unsafe_h : {}
        unsupported_keys = raw_parameters.keys - allowed_keys
        return if unsupported_keys.empty?

        field = "#{prefix}.#{unsupported_keys.first}"
        raise ValidationError.new(field:, message: t('api.errors.unsupported_attribute'))
      end
    end
  end
end
