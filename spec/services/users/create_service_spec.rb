# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::CreateService do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
    ensure_staff_authorization_reference_data!
  end

  after do
    clear_enqueued_jobs
  end

  def call(actor:, attributes:)
    described_class.call(actor:, attributes:, request_id: SecureRandom.uuid)
  end

  it 'creates an invited staff user, records an audit event, and enqueues invitation delivery' do
    actor = create(:user, role: 'admin')

    user = call(actor:, attributes: { email: 'new.staff@example.com', role: 'hr' })

    expect(user).to be_persisted
    expect(user.email).to eq('new.staff@example.com')
    expect(user.staff_state).to eq('invited')
    expect(user.invited_by).to eq(actor)
    expect(AuditEvent.where(action_code: 'staff_user_invited', entity_type: 'User', entity_id: user.id)).to exist
    expect(Users::InvitationDeliveryJob).to have_been_enqueued.with(user.id)
  end

  it 'raises a field-addressable validation error when the email is already taken' do
    actor = create(:user, role: 'admin')
    create(:user, email: 'duplicate.staff@example.com')

    expect do
      call(actor:, attributes: { email: 'duplicate.staff@example.com', role: 'finance' })
    end.to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.attribute_names).to include(:email) }
  end

  it 'translates a database uniqueness race into a field-addressable validation error' do
    actor = create(:user, role: 'admin')
    race_error_message = 'duplicate key value violates unique constraint'

    allow(User).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique, race_error_message)

    expect { call(actor:, attributes: { email: 'race@example.com', role: 'finance' }) }.to raise_error(
      ActiveRecord::RecordInvalid
    ) do |error|
      expect(error.record.email).to eq('race@example.com')
      expect(error.record.errors.attribute_names).to include(:email)
    end
  end
end
