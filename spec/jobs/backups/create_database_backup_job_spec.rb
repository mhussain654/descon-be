# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backups::CreateDatabaseBackupJob do
  # Never shells out to a real pg_dump/psql in the test suite (AGENTS.md: "do not call real ...
  # services from tests") -- stub Open3.capture3 to write a small fixture file where pg_dump
  # would have written its dump, and assert on the job's own behavior around that boundary.
  def stub_successful_pg_dump
    allow(Open3).to receive(:capture3) do |*args|
      dump_path = args[args.index('--file') + 1]
      File.write(dump_path, '-- fake dump content')
      ['', '', instance_double(Process::Status, success?: true)]
    end
  end

  def stub_failing_pg_dump
    allow(Open3).to receive(:capture3).and_return(['', 'connection refused',
                                                   instance_double(Process::Status, success?: false)])
  end

  describe '#perform' do
    it 'creates a succeeded backup with a real attached archive, byte size and checksum' do
      stub_successful_pg_dump

      expect { described_class.new.perform('2026-09-06') }.to change(SystemDatabaseBackup, :count).by(1)

      backup = SystemDatabaseBackup.last
      expect(backup.status_code).to eq('succeeded')
      expect(backup.archive).to be_attached
      expect(backup.byte_size).to be_positive
      expect(backup.checksum_sha256).to be_present
      expect(backup.duration_seconds).to be_a(Integer)
    end

    it 'marks the backup failed and does not retry when pg_dump itself fails' do
      stub_failing_pg_dump

      expect { described_class.new.perform('2026-09-06') }.not_to raise_error

      backup = SystemDatabaseBackup.last
      expect(backup.status_code).to eq('failed')
      expect(backup.error_message).to eq('pg_dump exited with a non-zero status')
      expect(backup.archive).not_to be_attached
    end

    it 'marks the backup failed and re-raises (for ActiveJob retry_on) when the post-attach step fails transiently' do
      stub_successful_pg_dump
      # Simulates a transient failure in the step immediately after the real (local-disk, in
      # test) attach succeeds -- e.g. a network hiccup mid-checksum against a remote store --
      # without a broad allow_any_instance_of stub.
      allow(Digest::SHA256).to receive(:file).and_raise(IOError, 'connection reset')

      expect { described_class.new.perform('2026-09-06') }.to raise_error(Backups::TransientBackupError)

      backup = SystemDatabaseBackup.last
      expect(backup.status_code).to eq('failed')
      expect(backup.archive).to be_attached
    end

    it 'does not create a second backup for a day that already has a succeeded one' do
      create(:system_database_backup, status_code: 'succeeded', taken_at: Time.zone.parse('2026-09-06 10:00'))
      stub_successful_pg_dump

      expect { described_class.new.perform('2026-09-06') }.not_to change(SystemDatabaseBackup, :count)
    end

    it 'allows a new attempt on a day whose only prior backup failed' do
      create(:system_database_backup, status_code: 'failed', taken_at: Time.zone.parse('2026-09-06 01:00'))
      stub_successful_pg_dump

      expect { described_class.new.perform('2026-09-06') }.to change(SystemDatabaseBackup, :count).by(1)
    end
  end
end
