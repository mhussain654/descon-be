# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::InvitationAcceptanceService do
  self.use_transactional_tests = false

  around do |example|
    AuditEvent.delete_all
    User.delete_all
    ensure_staff_authorization_reference_data!
    example.run
  ensure
    AuditEvent.delete_all
    User.delete_all
  end

  def accept(token:, password: 'Password123!', password_confirmation: 'Password123!')
    described_class.call(
      token:,
      password:,
      password_confirmation:,
      request_id: SecureRandom.uuid
    )
  end

  it 'activates an invited user with a valid invitation token' do
    user = create(:user, :invited, email: 'invitee@example.com')
    raw_token = SecureRandom.urlsafe_base64(32)
    user.update!(
      invitation_token_digest: Digest::SHA256.hexdigest(raw_token),
      invitation_expires_at: User::INVITATION_TTL.from_now
    )

    result = accept(token: raw_token)

    expect(result.reload.staff_state).to eq('active')
    expect(result).to be_active
    expect(result.valid_password?('Password123!')).to be(true)
    expect(result.invitation_token_digest).to be_nil
    expect(result.invitation_expires_at).to be_nil
    expect(result.invitation_accepted_at).to be_present
    expect(AuditEvent.where(action_code: 'staff_user_activated', entity_type: 'User', entity_id: user.id)).to exist
  end

  it 'rejects an expired invitation token' do
    user = create(:user, :invited, email: 'expired-invitee@example.com')
    raw_token = SecureRandom.urlsafe_base64(32)
    user.update!(
      invitation_token_digest: Digest::SHA256.hexdigest(raw_token),
      invitation_expires_at: 1.minute.ago
    )

    expect { accept(token: raw_token) }.to raise_error(InvalidInvitationError)
  end

  it 'rejects a reused invitation token after successful acceptance' do
    user = create(:user, :invited, email: 'single-use-invitee@example.com')
    raw_token = SecureRandom.urlsafe_base64(32)
    user.update!(
      invitation_token_digest: Digest::SHA256.hexdigest(raw_token),
      invitation_expires_at: User::INVITATION_TTL.from_now
    )

    accept(token: raw_token)

    expect { accept(token: raw_token) }.to raise_error(InvalidInvitationError)
  end
end
