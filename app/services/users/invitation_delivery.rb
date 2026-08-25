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

      raw_token = SecureRandom.urlsafe_base64(32)
      prepare_invitation!(user, raw_token)
      deliver_invitation!(user, raw_token)
      mark_invitation_sent!(user)
      user
    rescue StandardError => e
      raise DeliveryError, e.message
    end

    private

    def prepare_invitation!(user, raw_token)
      User.transaction do
        user.lock!
        return unless user.invited?

        user.update!(invitation_token_digest: token_digest(raw_token), invitation_expires_at: User::INVITATION_TTL.from_now)
      end
    end

    def deliver_invitation!(user, raw_token)
      StaffInvitationMailer.with(user:, invitation_token: raw_token).invitation_email.deliver_now
    end

    def mark_invitation_sent!(user)
      user.update!(invitation_sent_at: Time.current)
    end

    def token_digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end
  end
end
