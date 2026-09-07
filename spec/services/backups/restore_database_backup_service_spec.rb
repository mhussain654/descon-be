# frozen_string_literal: true

require 'rails_helper'
require 'zlib'
require 'stringio'

RSpec.describe Backups::RestoreDatabaseBackupService do
  def gzipped_sql_backup
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) { |gz| gz.write('-- fake sql dump') }
    io.string
  end

  it 'downloads and restores the archive via psql, never calling the real command in tests' do
    backup = create(:system_database_backup, :with_archive)
    allow(backup.archive).to receive(:download).and_return(gzipped_sql_backup)
    allow(Open3).to receive(:capture3).and_return(['', '', instance_double(Process::Status, success?: true)])

    expect { described_class.call(backup:) }.not_to raise_error
    expect(Open3).to have_received(:capture3)
  end

  it 'raises PermanentBackupError when psql fails' do
    backup = create(:system_database_backup, :with_archive)
    allow(backup.archive).to receive(:download).and_return(gzipped_sql_backup)
    allow(Open3).to receive(:capture3).and_return(['', 'syntax error',
                                                   instance_double(Process::Status, success?: false)])

    expect { described_class.call(backup:) }.to raise_error(Backups::PermanentBackupError)
  end
end
