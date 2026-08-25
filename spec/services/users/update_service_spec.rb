# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::UpdateService do
  self.use_transactional_tests = false

  around do |example|
    AuditEvent.delete_all
    RefreshToken.delete_all
    Session.delete_all
    User.delete_all
    ensure_staff_authorization_reference_data!
    example.run
  ensure
    AuditEvent.delete_all
    RefreshToken.delete_all
    Session.delete_all
    User.delete_all
  end

  def call(actor:, user:, attributes:)
    described_class.call(actor:, user:, attributes:, request_id: SecureRandom.uuid)
  end

  it 'revokes only the target user sessions on role change' do
    actor = create(:user, role: 'admin')
    target = create(:user, role: 'hr')
    target_session = create(:session, user: target)
    Authentication::RefreshTokenIssuer.call(session: target_session)
    unrelated = create(:user, role: 'mps')
    unrelated_session = create(:session, user: unrelated)
    Authentication::RefreshTokenIssuer.call(session: unrelated_session)

    result = call(actor:, user: target, attributes: { role: 'finance' })

    expect(result.role).to eq('finance')
    expect(target_session.reload).to be_revoked
    expect(unrelated_session.reload).not_to be_revoked
    expect(AuditEvent.where(action_code: 'staff_user_role_changed', entity_type: 'User', entity_id: target.id)).to exist
  end

  it 'revokes only the target user sessions on suspension' do
    actor = create(:user, role: 'admin')
    target = create(:user, role: 'hr')
    target_session = create(:session, user: target)
    Authentication::RefreshTokenIssuer.call(session: target_session)
    unrelated = create(:user, role: 'mps')
    unrelated_session = create(:session, user: unrelated)
    Authentication::RefreshTokenIssuer.call(session: unrelated_session)

    result = call(actor:, user: target, attributes: { staff_state: 'suspended' })

    expect(result.staff_state).to eq('suspended')
    expect(result).not_to be_active
    expect(target_session.reload).to be_revoked
    expect(unrelated_session.reload).not_to be_revoked
    expect(AuditEvent.where(action_code: 'staff_user_suspended', entity_type: 'User', entity_id: target.id)).to exist
  end

  it 'rejects self-suspension' do
    actor = create(:user, role: 'admin')

    expect do
      call(actor:, user: actor, attributes: { staff_state: 'suspended' })
    end.to raise_error(ValidationError) { |error| expect(error.field).to eq('user.staff_state') }
  end

  it 'rejects suspending the final active admin' do
    actor = create(:user, role: 'admin')

    expect do
      call(actor:, user: actor, attributes: { staff_state: 'suspended' })
    end.to raise_error(ValidationError, I18n.t('api.errors.last_active_admin'))
  end

  it 'rejects demoting the final active admin' do
    actor = create(:user, role: 'admin')

    expect do
      call(actor:, user: actor, attributes: { role: 'hr' })
    end.to raise_error(ValidationError, I18n.t('api.errors.last_active_admin'))
  end

  it 'prevents concurrent requests from bypassing the last-admin invariant' do
    admin_a = create(:user, role: 'admin', email: 'admin-a@example.com')
    admin_b = create(:user, role: 'admin', email: 'admin-b@example.com')
    outcomes = Queue.new

    worker = lambda do |actor:, user:, attributes:|
      ActiveRecord::Base.connection_pool.with_connection do
        call(actor:, user:, attributes:)
        outcomes << :success
      rescue ValidationError => e
        outcomes << e.code
      end
    end

    threads = [
      Thread.new { worker.call(actor: admin_a, user: admin_b, attributes: { role: 'hr' }) },
      Thread.new { worker.call(actor: admin_b, user: admin_a, attributes: { staff_state: 'suspended' }) }
    ]
    threads.each(&:join)

    results = Array.new(2) { outcomes.pop }

    expect(results.count(:success)).to eq(1)
    expect(results.count('validation_failed')).to eq(1)
    expect(User.where(role: 'admin', staff_state: 'active').count).to eq(1)
  end
end
