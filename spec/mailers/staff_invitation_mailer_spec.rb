# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StaffInvitationMailer do
  it 'renders the invitation token in the email body without persisting it' do
    user = build_stubbed(:user, :invited, email: 'mailer-invite@example.com', role: 'hr')
    email = described_class.with(user:, invitation_token: 'raw-token-123').invitation_email

    expect(email.to).to eq([user.email])
    expect(email.subject).to eq(I18n.t('api.users.mailer.subject'))
    expect(email.body.encoded).to include('raw-token-123')
  end
end
