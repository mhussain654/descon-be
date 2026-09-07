# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'backups:restore rake task' do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  before do
    Rake::Task['backups:restore'].reenable
  end

  it 'aborts with no public_id given' do
    expect { Rake::Task['backups:restore'].invoke }.to raise_error(SystemExit)
  end

  it 'aborts when no backup exists with the given public_id' do
    expect { Rake::Task['backups:restore'].invoke('does-not-exist') }.to raise_error(SystemExit)
  end

  it 'aborts when the backup has no attached archive' do
    backup = create(:system_database_backup, status_code: 'failed')

    expect { Rake::Task['backups:restore'].invoke(backup.public_id) }.to raise_error(SystemExit)
  end

  it 'invokes the restore service and prints a confirmation for a valid backup' do
    backup = create(:system_database_backup, :with_archive)
    allow(Backups::RestoreDatabaseBackupService).to receive(:call).with(backup:)

    expect { Rake::Task['backups:restore'].invoke(backup.public_id) }.to output(/Restored backup/).to_stdout
    expect(Backups::RestoreDatabaseBackupService).to have_received(:call).with(backup:)
  end
end
