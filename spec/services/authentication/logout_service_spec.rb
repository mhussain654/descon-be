# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Authentication::LogoutService do
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
    it 'allows concurrent logout calls to safely succeed while recording one logout event' do
      user = create(:user)
      session = create(:session, user:)
      token = create(:refresh_token, session:)
      outcomes = Queue.new

      worker = lambda do
        ActiveRecord::Base.connection_pool.with_connection do
          result = described_class.call(
            session: Session.find(session.id),
            request_id: SecureRandom.uuid,
            user_agent: 'RSpec',
            ip_address: '10.0.0.1'
          )
          outcomes << result.public_id
        end
      end

      threads = Array.new(2) { Thread.new(&worker) }
      threads.each(&:join)

      expect(Array.new(2) { outcomes.pop }).to all eq(session.public_id)
      expect(session.reload).to be_revoked
      expect(token.reload.revoked_at).to be_present
      expect(AuthenticationEvent.where(event_code: 'logout_succeeded').count).to eq(1)
    end
  end
end
