# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Authentication::LoginService do
  describe '.call' do
    let(:request_id) { SecureRandom.uuid }

    it 'creates the session, refresh token, and authentication event transactionally' do
      user = create(:user, password: 'Password123!')
      allow(Authentication::RefreshTokenIssuer).to receive(:call).and_raise(StandardError, 'boom')

      expect do
        described_class.call(
          email: user.email,
          password: 'Password123!',
          user_agent: 'RSpec',
          ip_address: '10.0.0.1',
          request_id:
        )
      end.to raise_error(StandardError, 'boom')

      expect(Session.where(user:).count).to eq(0)
      expect(RefreshToken.count).to eq(0)
      expect(AuthenticationEvent.count).to eq(0)
    end

    it 'records a masked failed-login event for an unknown email' do
      expect do
        described_class.call(
          email: 'missing@example.com',
          password: 'Password123!',
          user_agent: 'RSpec',
          ip_address: '10.0.0.1',
          request_id:
        )
      end.to raise_error(UnauthorizedError)

      event = AuthenticationEvent.order(:created_at).last
      expect(event.event_code).to eq('login_failed')
      expect(event.identifier_masked).to eq('m*****g@example.com')
      expect(event.user).to be_nil
    end

    it 'performs the dummy bcrypt comparison for an unknown email' do
      allow(BCrypt::Password).to receive(:new).with(described_class::DUMMY_PASSWORD_DIGEST).and_call_original

      expect do
        described_class.call(
          email: 'missing@example.com',
          password: 'Password123!',
          user_agent: 'RSpec',
          ip_address: '10.0.0.1',
          request_id:
        )
      end.to raise_error(UnauthorizedError)

      expect(BCrypt::Password).to have_received(:new).with(described_class::DUMMY_PASSWORD_DIGEST)
    end

    it 'sanitizes malformed and oversized user-agent input before persistence' do
      user = create(:user, password: 'Password123!')
      malformed_user_agent = ("Agent\xC3".b * 200).force_encoding('UTF-8')

      result = described_class.call(
        email: user.email,
        password: 'Password123!',
        user_agent: malformed_user_agent,
        ip_address: '10.0.0.1',
        request_id:
      )

      session = result.fetch(:session)
      event = AuthenticationEvent.order(:created_at).last

      expect(session.user_agent.length).to eq(Authentication::RequestContextSanitizer::MAX_USER_AGENT_LENGTH)
      expect(session.user_agent).to be_valid_encoding
      expect(event.user_agent.length).to eq(Authentication::RequestContextSanitizer::MAX_USER_AGENT_LENGTH)
      expect(event.user_agent).to be_valid_encoding
    end
  end
end
