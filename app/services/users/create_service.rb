# frozen_string_literal: true

module Users
  class CreateService < ApplicationService
    def initialize(actor:, attributes:, request_id:)
      @actor = actor
      @attributes = attributes
      @request_id = request_id
    end

    def call
      user = create_user_with_audit!
      InvitationDeliveryJob.perform_later(user.id)
      user
    rescue ActiveRecord::RecordNotUnique
      raise duplicate_email_error
    end

    private

    def create_user_with_audit!
      User.transaction do
        user = User.create!(
          email: @attributes.fetch(:email),
          role: @attributes.fetch(:role),
          staff_state: 'invited',
          invited_by: @actor
        )
        audit_invitation!(user)
        user
      end
    end

    def audit_invitation!(user)
      AuditLogger.call(
        action_code: 'staff_user_invited',
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
