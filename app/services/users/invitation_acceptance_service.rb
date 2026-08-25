# frozen_string_literal: true

module Users
  class InvitationAcceptanceService < ApplicationService
    def initialize(token:, password:, password_confirmation:, request_id:)
      @token = token.to_s
      @password = password
      @password_confirmation = password_confirmation
      @request_id = request_id
    end

    def call
      user = User.find_by(invitation_token_digest: token_digest(@token))
      raise InvalidInvitationError unless user

      activate_user!(user)
      user
    end

    private

    def activate_user!(user)
      User.transaction do
        user.lock!
        raise InvalidInvitationError unless acceptable_invitation?(user)

        apply_acceptance!(user)
        audit_activation!(user)
      end
    end

    def apply_acceptance!(user)
      user.password = @password
      user.password_confirmation = @password_confirmation
      user.staff_state = 'active'
      user.invitation_token_digest = nil
      user.invitation_expires_at = nil
      user.invitation_accepted_at = Time.current
      user.save!
    end

    def audit_activation!(user)
      AuditLogger.call(
        action_code: 'staff_user_activated',
        actor: user,
        target: user,
        request_id: @request_id,
        changes: { before: { staff_state: 'invited' }, after: { staff_state: 'active' } }
      )
    end

    def token_digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end

    def acceptable_invitation?(user)
      user.invited? &&
        user.invitation_token_digest.present? &&
        user.invitation_expires_at.present? &&
        user.invitation_expires_at.future?
    end
  end
end
