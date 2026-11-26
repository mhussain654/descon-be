# frozen_string_literal: true

module Users
  # The developer role is given only from the Rails console: through the staff
  # API nobody can assign it, and a developer account cannot be changed. Nor
  # can anyone give a role above their own (staff hierarchy, User#visible_staff_role_codes).
  module DeveloperRoleGuard
    module_function

    def ensure_assignable!(role, actor: nil)
      if role.to_s == 'developer'
        raise ValidationError.new(field: 'user.role', message: I18n.t('api.errors.developer_role_not_assignable'))
      end
      return if actor.nil? || User::STAFF_ROLE_CODES.exclude?(role.to_s) # unknown roles fail the model's own check
      return if actor.visible_staff_role_codes.include?(role.to_s)

      raise ValidationError.new(field: 'user.role', message: I18n.t('api.errors.role_above_own'))
    end

    def ensure_update_allowed!(user:, role:, actor: nil)
      if user.role == 'developer'
        raise ValidationError.new(field: 'user.role', message: I18n.t('api.errors.developer_account_not_manageable'))
      end

      ensure_assignable!(role, actor:)
    end
  end
end
