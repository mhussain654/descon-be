# frozen_string_literal: true

module Users
  class InvitationDelivery < ApplicationService
    class DeliveryError < StandardError; end
    CACHE_NAMESPACE = 'staff_invitation_tokens'

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
      cached_token = cached_invitation_token_for(user)
      return cached_token if cached_token.present?
      return nil if user.invitation_sent_at.present?

      issue_invitation_token!(user, reset_sent_at: false)
    end

    def cached_invitation_token_for(user)
      Rails.cache.read(invitation_token_cache_key(user))
    end

    def cache_invitation_token(user, raw_token)
      expires_in = [user.invitation_expires_at.to_i - Time.current.to_i, 1].max
      Rails.cache.write(invitation_token_cache_key(user), raw_token, expires_in:)
    end

    def invitation_token_cache_key(user)
      [CACHE_NAMESPACE, user.public_id, user.invitation_token_digest].join(':')
    end

    def generate_token
      SecureRandom.urlsafe_base64(32)
    end

    def issue_invitation_token!(user, reset_sent_at: true)
      raw_token = generate_token
      attributes = {
        invitation_token_digest: token_digest(raw_token),
        invitation_expires_at: User::INVITATION_TTL.from_now
      }
      attributes[:invitation_sent_at] = nil if reset_sent_at
      user.update!(attributes)
      cache_invitation_token(user, raw_token)
      raw_token
    end

    def token_digest(raw_token)
      Digest::SHA256.hexdigest(raw_token)
    end
  end
end
