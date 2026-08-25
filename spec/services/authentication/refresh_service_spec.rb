# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Authentication::RefreshService do
  self.use_transactional_tests = false

  around do |example|
    AuthenticationEvent.delete_all
    RefreshToken.delete_all
    Session.delete_all
    User.delete_all
    example.run
  ensure
    AuthenticationEvent.delete_all
    RefreshToken.delete_all
    Session.delete_all
    User.delete_all
  end

  describe '.call' do
    let(:request_id) { SecureRandom.uuid }

    def refresh(raw_token)
      described_class.call(
        refresh_token: raw_token,
        user_agent: 'RSpec',
        ip_address: '10.0.0.1',
        request_id:
      )
    end

    it 'allows only one concurrent success for the same refresh token' do
      user = create(:user, password: 'Password123!')
      session = create(:session, user:)
      raw_token = Authentication::RefreshTokenIssuer.call(session:)
      outcomes = Queue.new

      worker = lambda do
        ActiveRecord::Base.connection_pool.with_connection do
          result = refresh(raw_token)
          outcomes << [:success, result.fetch(:refresh_token)]
        rescue InvalidRefreshTokenError => e
          outcomes << [:error, e.code]
        end
      end

      threads = Array.new(2) { Thread.new(&worker) }
      threads.each(&:join)
      results = Array.new(2) { outcomes.pop }

      expect(results.count { |type, _| type == :success }).to eq(1)
      expect(results.count { |type, code| type == :error && code == 'invalid_refresh_token' }).to eq(1)
      expect(session.reload).to be_revoked
      expect(AuthenticationEvent.where(event_code: 'refresh_token_reuse_detected').count).to eq(1)
    end

    it 'rolls back rotation if replacement-token persistence fails' do
      user = create(:user, password: 'Password123!')
      session = create(:session, user:)
      raw_token = Authentication::RefreshTokenIssuer.call(session:)
      original_token = RefreshToken.find_by!(token_digest: Digest::SHA256.hexdigest(raw_token))
      allow(Authentication::RefreshTokenIssuer).to receive(:call).and_raise(StandardError, 'boom')

      expect { refresh(raw_token) }.to raise_error(StandardError, 'boom')

      expect(original_token.reload).not_to be_rotated
      expect(session.reload).not_to be_revoked
      expect(RefreshToken.count).to eq(1)
      expect(AuthenticationEvent.count).to eq(0)
    end

    it 'rejects refresh for an inactive user, revokes the session, and records the failure event' do
      user = create(:user, password: 'Password123!', active: false)
      session = create(:session, user:)
      raw_token = Authentication::RefreshTokenIssuer.call(session:)

      expect { refresh(raw_token) }.to raise_error(InactiveAccountError)

      expect(session.reload).to be_revoked
      expect(AuthenticationEvent.order(:created_at).pluck(:event_code, :metadata)).to include(
        ['refresh_failed', { 'reason' => 'inactive_account' }]
      )
    end

    it 'records refresh_failed for an expired token' do
      user = create(:user, password: 'Password123!')
      session = create(:session, user:)
      raw_token = Authentication::RefreshTokenIssuer.call(session:)
      RefreshToken.last.update!(expires_at: 1.minute.ago)

      expect { refresh(raw_token) }.to raise_error(InvalidRefreshTokenError)

      expect(AuthenticationEvent.order(:created_at).pluck(:event_code, :metadata)).to include(
        ['refresh_failed', { 'reason' => 'expired_refresh_token' }]
      )
    end

    it 'records refresh_failed for a revoked token' do
      user = create(:user, password: 'Password123!')
      session = create(:session, user:)
      raw_token = Authentication::RefreshTokenIssuer.call(session:)
      RefreshToken.last.update!(revoked_at: Time.current)

      expect { refresh(raw_token) }.to raise_error(InvalidRefreshTokenError)

      expect(AuthenticationEvent.order(:created_at).pluck(:event_code, :metadata)).to include(
        ['refresh_failed', { 'reason' => 'revoked_refresh_token' }]
      )
    end

    it 'records refresh_failed when the session was already revoked' do
      user = create(:user, password: 'Password123!')
      session = create(:session, user:)
      raw_token = Authentication::RefreshTokenIssuer.call(session:)
      session.revoke!

      expect { refresh(raw_token) }.to raise_error(RevokedSessionError)

      expect(AuthenticationEvent.order(:created_at).pluck(:event_code, :metadata)).to include(
        ['refresh_failed', { 'reason' => 'session_revoked' }]
      )
    end

    it 'records refresh_failed when the refresh token digest is unknown' do
      expect { refresh(SecureRandom.hex(32)) }.to raise_error(InvalidRefreshTokenError)

      expect(AuthenticationEvent.order(:created_at).pluck(:event_code, :metadata)).to include(
        ['refresh_failed', { 'reason' => 'token_not_found' }]
      )
    end

    it 'sanitizes malformed and oversized user-agent input before persistence on refresh' do
      user = create(:user, password: 'Password123!')
      session = create(:session, user:)
      raw_token = Authentication::RefreshTokenIssuer.call(session:)
      malformed_user_agent = ("Refresh\xC3".b * 200).force_encoding('UTF-8')

      result = described_class.call(
        refresh_token: raw_token,
        user_agent: malformed_user_agent,
        ip_address: '10.0.0.1',
        request_id:
      )

      refreshed_session = result.fetch(:session)
      event = AuthenticationEvent.order(:created_at).last

      expect(refreshed_session.user_agent.length).to eq(Authentication::RequestContextSanitizer::MAX_USER_AGENT_LENGTH)
      expect(refreshed_session.user_agent).to be_valid_encoding
      expect(event.user_agent.length).to eq(Authentication::RequestContextSanitizer::MAX_USER_AGENT_LENGTH)
      expect(event.user_agent).to be_valid_encoding
    end
  end
end
