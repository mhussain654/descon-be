# frozen_string_literal: true

module Users
  class UpdateService < ApplicationService
    STATE_CHANGE_ACTION_CODES = {
      %w[active suspended] => 'staff_user_suspended',
      %w[suspended active] => 'staff_user_reactivated'
    }.freeze

    def initialize(actor:, user:, attributes:, request_id:)
      @actor = actor
      @user = user
      @attributes = attributes.compact_blank
      @request_id = request_id
    end

    def call = User.transaction { persist_update! }

    private

    def persist_update!
      updated_user = locked_user
      before_state = audit_state(updated_user)
      updated_user.assign_attributes(@attributes)
      protect_last_active_admin!(updated_user, before_state:)
      validate_state_transition!(updated_user, before_state:)
      updated_user.save!
      revoke_sessions_if_needed!(updated_user, before_state:)
      write_audit_events!(updated_user, before_state:)
      updated_user
    end

    def locked_user
      return @locked_user if defined?(@locked_user)

      @locked_user = if active_admin_lock_required?
                       lock_active_admins_for_update.find { |user| user.id == @user.id } || User.lock.find(@user.id)
                     else
                       User.lock.find(@user.id)
                     end
    end

    def validate_state_transition!(user, before_state:)
      raise_invalid_staff_state! if user.staff_state == 'invited' && before_state[:staff_state] != 'invited'

      if before_state[:staff_state] == 'invited' && user.staff_state != 'invited'
        raise_invited_transition_error!(before_state)
      end

      return unless @actor.id == user.id && user.staff_state == 'suspended'

      raise ValidationError.new(field: 'user.staff_state', message: I18n.t('api.errors.self_suspension_forbidden'))
    end

    def protect_last_active_admin!(user, before_state:)
      return unless last_admin_rule_relevant?(user, before_state:)

      active_admins = @locked_active_admins || lock_active_admins_for_update
      return unless active_admins.one? && active_admins.first.id == user.id

      raise ValidationError.new(field: last_admin_field(user), message: I18n.t('api.errors.last_active_admin'))
    end

    def last_admin_rule_relevant?(user, before_state:)
      before_state[:role] == 'admin' &&
        before_state[:staff_state] == 'active' &&
        (user.role != 'admin' || user.staff_state == 'suspended')
    end

    def revoke_sessions_if_needed!(user, before_state:)
      return unless before_state[:staff_state] == 'active'
      return unless before_state[:role] != user.role || user.staff_state == 'suspended'

      SessionRevoker.call(user:)
    end

    def write_audit_events!(user, before_state:)
      write_role_change_audit!(user, before_state:)
      write_state_change_audit!(user, before_state:)
    end

    def audit_state(user) = { role: user.role, staff_state: user.staff_state }

    def last_admin_field(user) = user.role == 'admin' ? 'user.staff_state' : 'user.role'

    def raise_invalid_staff_state!
      raise ValidationError.new(field: 'user.staff_state', message: I18n.t('api.errors.staff_state_invalid'))
    end

    def raise_invited_transition_error!(before_state)
      return unless before_state[:staff_state] == 'invited'

      raise ValidationError.new(
        field: 'user.staff_state',
        message: I18n.t('api.errors.staff_state_transition_invalid')
      )
    end

    def write_role_change_audit!(user, before_state:)
      return if before_state[:role] == user.role

      AuditLogger.call(
        action_code: 'staff_user_role_changed',
        actor: @actor,
        target: user,
        request_id: @request_id,
        changes: { before: { role: before_state[:role] }, after: { role: user.role } }
      )
    end

    def write_state_change_audit!(user, before_state:)
      action_code = state_change_action_code(before_state[:staff_state], user.staff_state)
      return unless action_code

      AuditLogger.call(
        action_code:,
        actor: @actor,
        target: user,
        request_id: @request_id,
        changes: { before: { staff_state: before_state[:staff_state] }, after: { staff_state: user.staff_state } }
      )
    end

    def state_change_action_code(previous_state, current_state)
      STATE_CHANGE_ACTION_CODES[[previous_state, current_state]]
    end

    def active_admin_lock_required? = @user.role == 'admin' && @user.staff_state == 'active'

    def lock_active_admins_for_update
      @lock_active_admins_for_update ||= User.where(role: 'admin', staff_state: 'active').order(:id).lock.to_a
    end
  end
end
