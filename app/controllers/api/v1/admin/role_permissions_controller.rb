# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Role permissions matrix (`manage_reference_data`): every staff role with
      # the permissions it has, and replacing one role's permissions. `locked`
      # is the developer role (always every permission); `own_role` is the
      # caller's own role, which they cannot change.
      class RolePermissionsController < ProtectedStaffController
        def index
          authorize :reference_data, :manage?, policy_class: ::Admin::ReferenceDataPolicy

          render_success(data: matrix)
        end

        def update
          authorize :reference_data, :manage?, policy_class: ::Admin::ReferenceDataPolicy

          ::Admin::RolePermissions::UpdateService.call(
            actor: current_user,
            role_code: params.expect(:role_code),
            permission_codes: params.fetch(:role_permission, {}).permit(permission_codes: [])[:permission_codes],
            request_id: request.request_id
          )
          render_success(data: matrix)
        end

        private

        def matrix
          roles = managed(Role).where(active: true).includes(:permissions).order(:id)
          {
            roles: roles.map { |role| serialized_role(role) },
            permissions: Permission.where(active: true).order(:id).map do |permission|
              serialized_permission(permission)
            end,
            grants: roles.to_h { |role| [role.code, granted_codes(role)] }
          }
        end

        def managed(model)
          policy_scope(model, policy_scope_class: ::Admin::ReferenceDataPolicy::ManagedScope)
        end

        def granted_codes(role) = role.permissions.select(&:active).map(&:code).sort

        def serialized_role(role)
          locked = ::Admin::RolePermissions::UpdateService::LOCKED_ROLE_CODES.include?(role.code)
          { code: role.code, name: role.name_for.presence || role.code.humanize, locked:,
            own_role: role.code == current_user.role }
        end

        def serialized_permission(permission)
          {
            code: permission.code,
            name: permission.name_for.presence || permission.code.humanize,
            developer_only: Permission::DEVELOPER_ONLY_PERMISSIONS.include?(permission.code)
          }
        end
      end
    end
  end
end
