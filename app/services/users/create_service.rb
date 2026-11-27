# frozen_string_literal: true

module Users
  # Adds a staff account. Normally an invitation: the account starts `invited` and the person sets their own
  # password from the emailed link. A developer may instead give a password, which creates the account `active`
  # straight away with no invitation sent (for staff who cannot receive the email); the password is never logged
  # or audited.
  class CreateService < ApplicationService
    def initialize(actor:, attributes:, request_id:)
      @actor = actor
      @attributes = attributes
      @request_id = request_id
    end

    def call
      DeveloperRoleGuard.ensure_assignable!(@attributes.fetch(:role), actor: @actor)
      raise ForbiddenError if direct? && @actor&.role != 'developer'

      user = create_user_with_audit!
      InvitationDeliveryJob.perform_later(user.id) unless direct?
      user
    rescue ActiveRecord::RecordNotUnique
      raise duplicate_email_error
    end

    private

    def direct? = @attributes[:password].present?

    def create_user_with_audit!
      User.transaction do
        user = User.create!(user_attributes)
        audit!(user)
        user
      end
    end

    def user_attributes
      base = { email: @attributes.fetch(:email), role: @attributes.fetch(:role), invited_by: @actor }
      return base.merge(staff_state: 'invited') unless direct?

      base.merge(staff_state: 'active', password: @attributes[:password],
                 password_confirmation: @attributes[:password_confirmation].to_s)
    end

    def audit!(user)
      AuditLogger.call(
        action_code: direct? ? 'staff_user_created' : 'staff_user_invited',
        actor: @actor,
        target: user,
        request_id: @request_id,
        changes: { after: audit_state(user) }
      )
    end

    def duplicate_email_error
      user = User.new(email: @attributes.fetch(:email))
      user.errors.add(:email, :taken)
      ActiveRecord::RecordInvalid.new(user)
    end

    def audit_state(user)
      { role: user.role, staff_state: user.staff_state }
    end
  end
end
