# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SystemDatabaseBackupPolicy do
  before do
    ensure_staff_authorization_reference_data!
  end

  describe '#index? and #access?' do
    it 'allows only admin -- backups are infra-sensitive, not even management/mps see them' do
      admin = create(:user, role: 'admin')
      denied_actors = %w[hr mps finance management].map { |role| create(:user, role:) }

      expect(described_class.new(admin, SystemDatabaseBackup).index?).to be(true)
      expect(described_class.new(admin, SystemDatabaseBackup).access?).to be(true)
      expect(denied_actors).to all(satisfy { |actor| described_class.new(actor, SystemDatabaseBackup).index? == false })
      expect(described_class.new(nil, SystemDatabaseBackup).index?).to be(false)
    end

    it 'denies an inactive admin' do
      inactive_admin = create(:user, role: 'admin', active: false)

      expect(described_class.new(inactive_admin, SystemDatabaseBackup).index?).to be(false)
    end
  end

  describe '::Scope' do
    it 'resolves the full scope for admin and none for any other role' do
      admin = create(:user, role: 'admin')
      management = create(:user, role: 'management')
      create(:system_database_backup)

      expect(described_class::Scope.new(admin, SystemDatabaseBackup.all).resolve.count).to eq(1)
      expect(described_class::Scope.new(management, SystemDatabaseBackup.all).resolve.count).to eq(0)
    end
  end
end
