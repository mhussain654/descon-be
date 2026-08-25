# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::InvitationDeliveryJob, type: :job do
  include ActiveJob::TestHelper

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

  it 'delivers an invitation email and stores only the token digest' do
    user = create(:user, :invited, email: 'job-invite@example.com')

    perform_enqueued_jobs do
      described_class.perform_later(user.id)
    end

    email = ActionMailer::Base.deliveries.last
    token = email.body.encoded[/Invitation token:\s+([A-Za-z0-9\-_]+)/, 1]

    expect(email.to).to eq([user.email])
    expect(token).to be_present
    expect(user.reload.invitation_token_digest).to eq(Digest::SHA256.hexdigest(token))
    expect(user.invitation_token_digest).not_to eq(token)
    expect(user.invitation_sent_at).to be_present
  end

  it 'does not place plaintext invitation tokens in job arguments' do
    user = create(:user, :invited, email: 'queued-invite@example.com')

    expect do
      described_class.perform_later(user.id)
    end.to have_enqueued_job(described_class).with(user.id)
  end

  it 'reuses the same active invitation token for duplicate delivery jobs' do
    user = create(:user, :invited, email: 'duplicate-job@example.com')

    described_class.perform_now(user.id)
    first_email = ActionMailer::Base.deliveries.last
    first_token = first_email.body.encoded[/Invitation token:\s+([A-Za-z0-9\-_]+)/, 1]

    described_class.perform_now(user.id)
    second_email = ActionMailer::Base.deliveries.last
    second_token = second_email.body.encoded[/Invitation token:\s+([A-Za-z0-9\-_]+)/, 1]

    expect(first_token).to be_present
    expect(second_token).to eq(first_token)
    expect(user.reload.invitation_token_digest).to eq(Digest::SHA256.hexdigest(first_token))
  end
end
