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
      email.body.encoded[/Invitation token:\s+([A-Za-z0-9\-_]+)/, 1]
    end

    expect(delivered_tokens.size).to eq(2)
    expect(delivered_tokens.uniq.size).to eq(1)
    expect(user.reload.invitation_token_digest).to eq(Digest::SHA256.hexdigest(delivered_tokens.first))
  end
end
