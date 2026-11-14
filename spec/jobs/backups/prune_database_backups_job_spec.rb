# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backups::PruneDatabaseBackupsJob do
  around { |example| travel_to(Time.zone.parse('2026-11-14 02:00 UTC')) { example.run } }

  def backup_on(day, status_code: 'succeeded')
    create(:system_database_backup, :with_archive, status_code:, taken_at: Time.zone.parse("#{day} 00:00:05 UTC"))
  end

  # One successful backup a night from 2026-03-01 to 2026-11-14.
  def nightly_backups
    (Date.new(2026, 3, 1)..Date.new(2026, 11, 14)).index_with { |day| backup_on(day.iso8601) }
  end

  it 'keeps the 14 newest backups and the first of each of the last 6 months, deleting the rest' do
    backups = nightly_backups

    described_class.new.perform

    newest = (Date.new(2026, 11, 1)..Date.new(2026, 11, 14)).to_a
    monthly = [Date.new(2026, 6, 1), Date.new(2026, 7, 1), Date.new(2026, 8, 1), Date.new(2026, 9, 1),
               Date.new(2026, 10, 1)]
    expect(SystemDatabaseBackup.pluck(:id)).to match_array((newest + monthly).map { |day| backups[day].id })
  end

  it 'removes the deleted backups\' files and records each deletion in the audit log' do
    backups = nightly_backups
    old_backup = backups[Date.new(2026, 5, 20)]
    blob_key = old_backup.archive.blob.key

    expect { described_class.new.perform }.to change(ActiveStorage::Blob, :count).by(-(backups.size - 19))

    expect(ActiveStorage::Blob.service.exist?(blob_key)).to be(false)
    expect(AuditEvent.where(action_code: 'system_database_backup_pruned', entity_id: old_backup.id).sole.metadata)
      .to include('backup_public_id' => old_backup.public_id, 'status_code' => 'succeeded')
  end

  it 'deletes failed attempts after 30 days but keeps recent ones, and never counts them as kept backups' do
    old_failure = backup_on('2026-10-01', status_code: 'failed')
    recent_failure = backup_on('2026-11-10', status_code: 'failed')
    succeeded = backup_on('2026-11-13')

    described_class.new.perform

    expect(SystemDatabaseBackup.pluck(:id)).to contain_exactly(recent_failure.id, succeeded.id)
    expect(SystemDatabaseBackup.exists?(old_failure.id)).to be(false)
  end

  it 'deletes nothing while there are 14 or fewer successful backups' do
    14.times { |i| backup_on((Date.new(2026, 1, 1) + i).iso8601) }

    expect { described_class.new.perform }.not_to change(SystemDatabaseBackup, :count)
  end

  it 'keeps the backup row when its file cannot be deleted, so a later run can try again' do
    nightly_backups
    s3_down = Aws::S3::Errors::ServiceError.new(nil, 'down')
    allow_any_instance_of(ActiveStorage::Attached::One).to receive(:purge).and_raise(s3_down) # rubocop:disable RSpec/AnyInstance

    expect { described_class.new.perform }.to raise_error(Aws::S3::Errors::ServiceError)
    expect(SystemDatabaseBackup.count).to eq(Date.new(2026, 3, 1).step(Date.new(2026, 11, 14)).count)
  end
end
