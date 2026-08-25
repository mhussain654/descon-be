# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::InvitationDelivery do
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ActionMailer::Base.deliveries.clear
    example.run
  ensure
    Rails.cache = original_cache
    ActionMailer::Base.deliveries.clear
  end

  before do
    ensure_staff_authorization_reference_data!
  end

  it 'does not store plaintext invitation tokens in Rails.cache' do
    user = create(:user, :invited, email: 'no-cache-invite@example.com')

    allow(Rails.cache).to receive(:read).and_call_original
    allow(Rails.cache).to receive(:write).and_call_original

    described_class.call(user_id: user.id)

    expect(Rails.cache).not_to have_received(:read)
    expect(Rails.cache).not_to have_received(:write)
  end

  it 'issues a new token and expiry once a prior invitation has expired' do
    user = create(:user, :invited, email: 'expired-invite@example.com')
    user.invitation_expires_at = 1.minute.ago
    expired_token = Users::InvitationToken.generate(user:)
    user.update!(
      invitation_token_digest: Digest::SHA256.hexdigest(expired_token),
      invitation_expires_at: 1.minute.ago,
      invitation_sent_at: 2.minutes.ago
    )

    described_class.call(user_id: user.id)

    delivered_token = ActionMailer::Base.deliveries.last.body.encoded[/Invitation token:\s+([A-Za-z0-9._-]+)/, 1]

    expect(delivered_token).to be_present
    expect(delivered_token).not_to eq(expired_token)
    expect(user.reload.invitation_expires_at).to be > Time.current
    expect(user.invitation_token_digest).to eq(Digest::SHA256.hexdigest(delivered_token))
  end

  it 'reuses the same invitation token across concurrent duplicate deliveries' do
    user = create(:user, :invited, email: 'concurrent-invite@example.com')

    worker = lambda do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.call(user_id: user.id)
      end
    end

    threads = [Thread.new(&worker), Thread.new(&worker)]
    threads.each(&:join)

    delivered_tokens = ActionMailer::Base.deliveries.last(2).map do |email|
      email.body.encoded[/Invitation token:\s+([A-Za-z0-9._-]+)/, 1]
    end

    expect(delivered_tokens.size).to eq(2)
    expect(delivered_tokens.uniq.size).to eq(1)
    expect(user.reload.invitation_token_digest).to eq(Digest::SHA256.hexdigest(delivered_tokens.first))
  end
end
