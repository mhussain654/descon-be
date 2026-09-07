# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'backups:restore rake task' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  around do |example|
    original = ENV.fetch('RESTORE_TARGET_DATABASE_URL', nil)
    example.run
    ENV['RESTORE_TARGET_DATABASE_URL'] = original
  end

  before do
    Rake::Task['backups:restore'].reenable
  end

  it 'aborts with no public_id given' do
    expect { Rake::Task['backups:restore'].invoke }.to raise_error(SystemExit)
  end

  it 'aborts when RESTORE_TARGET_DATABASE_URL is not set -- never falls back to this process\'s own database' do
    ENV.delete('RESTORE_TARGET_DATABASE_URL')
    backup = create(:system_database_backup, :with_archive)

    expect { Rake::Task['backups:restore'].invoke(backup.public_id) }.to raise_error(SystemExit)
  end

  it 'aborts when no backup exists with the given public_id' do
    ENV['RESTORE_TARGET_DATABASE_URL'] = 'postgres://user:pw@isolated-host:5432/restore_target'

    expect { Rake::Task['backups:restore'].invoke('does-not-exist') }.to raise_error(SystemExit)
  end

  it 'aborts when the backup has no attached archive' do
    ENV['RESTORE_TARGET_DATABASE_URL'] = 'postgres://user:pw@isolated-host:5432/restore_target'
    backup = create(:system_database_backup, status_code: 'failed')

    expect { Rake::Task['backups:restore'].invoke(backup.public_id) }.to raise_error(SystemExit)
  end

  it 'invokes the restore service with the explicit target and prints a confirmation for a valid backup' do
    ENV['RESTORE_TARGET_DATABASE_URL'] = 'postgres://user:pw@isolated-host:5432/restore_target'
    backup = create(:system_database_backup, :with_archive)
    allow(Backups::RestoreDatabaseBackupService).to receive(:call)
      .with(backup:, target_database_url: 'postgres://user:pw@isolated-host:5432/restore_target')

    expect { Rake::Task['backups:restore'].invoke(backup.public_id) }.to output(/Restored backup/).to_stdout
    expect(Backups::RestoreDatabaseBackupService).to have_received(:call)
      .with(backup:, target_database_url: 'postgres://user:pw@isolated-host:5432/restore_target')
  end

  it 'never prints the target connection string\'s credentials to stdout' do
    ENV['RESTORE_TARGET_DATABASE_URL'] = 'postgres://user:supersecret@isolated-host:5432/restore_target'
    backup = create(:system_database_backup, :with_archive)
    allow(Backups::RestoreDatabaseBackupService).to receive(:call)

    output = capture_stdout { Rake::Task['backups:restore'].invoke(backup.public_id) }

    expect(output).not_to include('supersecret')
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
