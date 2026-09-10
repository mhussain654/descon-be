# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditEventPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#index?' do
    it 'allows staff with an active view_audit_events permission (admin, management)' do
      admin = create(:user, role: 'admin')
      management = create(:user, role: 'management')
      denied_actors = %w[hr mps finance].map { |role| create(:user, role:) }

      expect(described_class.new(admin, AuditEvent).index?).to be(true)
      expect(described_class.new(management, AuditEvent).index?).to be(true)
      expect(denied_actors).to all(satisfy { |actor| described_class.new(actor, AuditEvent).index? == false })
      expect(described_class.new(nil, AuditEvent).index?).to be(false)
    end

    it 'denies an inactive user' do
      inactive_management = create(:user, role: 'management', active: false)

      expect(described_class.new(inactive_management, AuditEvent).index?).to be(false)
    end

    it 'denies a user when the view_audit_events permission record is inactive' do
      management = create(:user, role: 'management')
      Permission.find_by!(code: 'view_audit_events').update!(active: false)

      expect(described_class.new(management, AuditEvent).index?).to be(false)
    end
  end

  describe '::Scope' do
    it 'resolves the full scope for a permitted actor and none for a denied one' do
      management = create(:user, role: 'management')
      hr = create(:user, role: 'hr')
      create(:audit_event)

      expect(described_class::Scope.new(management, AuditEvent.all).resolve.count).to eq(1)
      expect(described_class::Scope.new(hr, AuditEvent.all).resolve.count).to eq(0)
    end
  end
end
