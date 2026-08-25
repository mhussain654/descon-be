# frozen_string_literal: true

module Users
  class InvitationToken
    class << self
      def generate(user:)
        expires_at = user.invitation_expires_at
        raise ArgumentError, 'invitation_expires_at is required' unless expires_at

        expires_at_epoch = expires_at.to_i
        signature = Base64.urlsafe_encode64(
          OpenSSL::HMAC.digest('SHA256', secret, token_payload(user.public_id, expires_at_epoch)),
          padding: false
        )

        "#{user.public_id}.#{expires_at_epoch}.#{signature}"
      end

      private

      def token_payload(public_id, expires_at_epoch)
        [public_id, expires_at_epoch].join(':')
      end

      def secret
        if Rails.env.production?
          ENV.fetch('INVITATION_TOKEN_SECRET')
        else
          ENV.fetch('INVITATION_TOKEN_SECRET') { ENV.fetch('JWT_SECRET', 'development-invitation-token-secret') }
        end
      end
    end
  end
end
