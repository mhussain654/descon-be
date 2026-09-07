# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin::SystemDatabaseBackups::AccessService do
  it 'returns a short-lived signed download URL and records an audit event' do
    user = create(:user, role: 'admin')
    backup = create(:system_database_backup, :with_archive)

    result = described_class.call(actor: user, backup:, request_id: 'req-1')

    expect(result.backup).to eq(backup)
    expect(result.url).to be_present
    expect(result.expires_at).to be_present

    event = AuditEvent.last
    expect(event.actor).to eq(user)
    expect(event.entity_type).to eq('SystemDatabaseBackup')
    expect(event.entity_id).to eq(backup.id)
    expect(event.action_code).to eq('system_database_backup_accessed')
    expect(event.metadata['backup_public_id']).to eq(backup.public_id)
  end

  it 'raises BackupArchiveNotFoundError when the backup has no attached archive' do
    user = create(:user, role: 'admin')
    backup = create(:system_database_backup)

    expect do
      described_class.call(actor: user, backup:, request_id: 'req-1')
    end.to raise_error(BackupArchiveNotFoundError)
  end
end
