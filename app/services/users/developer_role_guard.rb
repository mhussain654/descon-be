# frozen_string_literal: true

module Users
  # The developer role is given only from the Rails console: through the staff
  # API nobody can assign it, and a developer account cannot be changed.
  module DeveloperRoleGuard
    module_function

    def ensure_assignable!(role)
      return unless role.to_s == 'developer'

      raise ValidationError.new(field: 'user.role', message: I18n.t('api.errors.developer_role_not_assignable'))
    end

    def ensure_update_allowed!(user:, role:)
      if user.role == 'developer'
        raise ValidationError.new(field: 'user.role', message: I18n.t('api.errors.developer_account_not_manageable'))
      end

      ensure_assignable!(role)
    end
  end
end
