# frozen_string_literal: true

module Api
  module V1
    # Lets authorized staff list, invite, and update other staff (internal) user accounts.
    class UsersController < ProtectedStaffController
      # Returns a paginated, policy-scoped list of staff users, filtered/sorted per query params.
      def index
        authorize User

        query = ::Users::IndexQuery.new(scope: policy_scope(User), params:)
        users = query.call

        render_payload(collection_payload(data: serialized_users(users), pagination: query.pagination))
      end

      # Creates (invites) a new staff user with the given email and role; idempotent per Idempotency-Key.
      def create
        authorize User
        render_idempotent_response(scope: 'users.create', subject: current_user) { create_payload }
      end

      # Updates an existing staff user's role and/or staff_state.
      def update
        authorize target_user, :update?
        render_success(data: update_payload)
      end

      private

      # Invites a new user via the create service and builds the created-user success payload.
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

      # Applies the requested changes via the update service and builds the updated-user response body.
      def update_payload
        updated_user = ::Users::UpdateService.call(
          actor: current_user,
          user: target_user,
          attributes: update_user_attributes,
          request_id: request.request_id
        )
        { user: serialized_user(updated_user), message: t('api.users.updated') }
      end

      # Validates that only the email/role keys were submitted, then returns the strong-params hash for creation.
      def create_user_attributes
        enforce_allowed_keys!(params[:user], allowed_keys: %w[email role], prefix: 'user')
        create_params.to_h.symbolize_keys
      end

      # Validates that only the role/staff_state keys were submitted, then returns the strong-params hash for update.
      def update_user_attributes
        enforce_allowed_keys!(params[:user], allowed_keys: %w[role staff_state], prefix: 'user')
        update_params.to_h.symbolize_keys
      end

      # Strong-params the fields allowed when creating a user.
      def create_params
        params.expect(user: %i[email role])
      end

      # Strong-params the fields allowed when updating a user.
      def update_params
        params.expect(user: %i[role staff_state])
      end

      # Looks up (and memoizes) the policy-scoped target user by public id, from the route param.
      def target_user
        @target_user ||= policy_scope(User).find_by!(public_id: params.expect(:id))
      end

      # Serializes a single user to its public JSON summary representation.
      def serialized_user(user)
        ::Users::SummarySerializer.new(user).as_json
      end

      # Serializes a collection of users to their public JSON summary representations.
      def serialized_users(users)
        users.map { |user| serialized_user(user) }
      end

      # Raises a validation error if the submitted parameter hash contains any key outside the allowed list,
      # guarding against silently-ignored or unsupported attributes being sent by the client.
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
