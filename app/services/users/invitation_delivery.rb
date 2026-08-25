# frozen_string_literal: true

module Users
  class InvitationDelivery < ApplicationService
    class DeliveryError < StandardError; end

    def initialize(user_id:)
      @user_id = user_id
    end

    def call
      user = User.find(@user_id)
      return unless user.invited?

      raw_token = prepare_invitation!(user)
      return unless raw_token

      deliver_invitation!(user, raw_token)
      mark_invitation_sent!(user)
      user
    rescue StandardError => e
      raise DeliveryError, e.message
    end

    private

    def prepare_invitation!(user)
      User.transaction do
        user.lock!
        return unless user.invited?
        return active_invitation_token_for(user) if user.invitation_active?

        issue_invitation_token!(user)
      end
    end

    def deliver_invitation!(user, raw_token)
      StaffInvitationMailer.with(user:, invitation_token: raw_token).invitation_email.deliver_now
    end

    def mark_invitation_sent!(user)
      user.update!(invitation_sent_at: Time.current)
    end

    def active_invitation_token_for(user)
      InvitationToken.generate(user:)
    end

    def issue_invitation_token!(user, reset_sent_at: true)
      invitation_expires_at = User::INVITATION_TTL.from_now
      user.invitation_expires_at = invitation_expires_at
      raw_token = InvitationToken.generate(user:)
      attributes = {
        invitation_expires_at:,
        invitation_token_digest: token_digest(raw_token)
      }
      attributes[:invitation_sent_at] = nil if reset_sent_at
      user.update!(attributes)
      raw_token
    end

    def token_digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end
  end
end
