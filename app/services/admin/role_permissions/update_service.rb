# frozen_string_literal: true

module Admin
  module RolePermissions
    # Replaces the permissions of one staff role (developer-only,
    # `manage_reference_data`). The developer role is locked to every
    # permission; developer-only permissions never go to another role; admin
    # always keeps `manage_staff_users` so someone can still manage staff.
    class UpdateService < ApplicationService
      LOCKED_ROLE_CODES = %w[developer].freeze
      ADMIN_REQUIRED_PERMISSIONS = %w[manage_staff_users].freeze

      def initialize(actor:, role_code:, permission_codes:, request_id: nil)
        @actor = actor
        @role_code = role_code.to_s
        @permission_codes = Array(permission_codes).map(&:to_s).uniq
        @request_id = request_id
      end

      def call
        validate_actor!
        role = Role.find_by!(code: @role_code)
        invalid!('role_permissions_locked') if LOCKED_ROLE_CODES.include?(role.code)

        permissions = requested_permissions
        validate_rules!(role, permissions)
        replace!(role, permissions)
        role
      end

      private

      def validate_actor!
        raise InactiveAccountError unless @actor&.active_staff_account?
        raise ForbiddenError unless @actor.permission?('manage_reference_data')
      end

      def requested_permissions
        permissions = Permission.where(code: @permission_codes, active: true).to_a
        invalid!('unknown_permission') unless permissions.size == @permission_codes.size
        permissions
      end

      def validate_rules!(role, permissions)
        codes = permissions.map(&:code)
        invalid!('developer_only_permission') if codes.intersect?(Permission::DEVELOPER_ONLY_PERMISSIONS)
        return unless role.code == 'admin' && !ADMIN_REQUIRED_PERMISSIONS.all? { |code| codes.include?(code) }

        invalid!('admin_needs_staff_management')
      end

      def replace!(role, permissions)
        Role.transaction do
          role.lock!
          before = role.permissions.pluck(:code).sort
          sync_grants!(role, permissions.map(&:id))
          record_audit!(role, before, permissions.map(&:code).sort)
        end
      end

      def sync_grants!(role, permission_ids)
        role.role_permissions.where.not(permission_id: permission_ids).delete_all
        (permission_ids - role.role_permissions.pluck(:permission_id)).each do |permission_id|
          role.role_permissions.create!(permission_id:)
        end
      end

      def record_audit!(role, before, after)
        AuditEvent.create!(
          actor: @actor,
          entity_type: 'Role',
          entity_id: role.id,
          action_code: 'role_permissions_update',
          metadata: { role: role.code, added: after - before, removed: before - after },
          request_id: @request_id,
          occurred_at: Time.current
        )
      end

      def invalid!(key)
        raise ValidationError.new(field: 'role_permission.permission_codes', message: I18n.t("api.errors.#{key}"))
      end
    end
  end
end
