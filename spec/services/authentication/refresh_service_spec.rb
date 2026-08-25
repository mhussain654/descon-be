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
  end
end
