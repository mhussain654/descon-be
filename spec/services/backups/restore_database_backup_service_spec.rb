# frozen_string_literal: true

require 'rails_helper'
require 'zlib'
require 'stringio'
require 'digest'
require 'pg'

RSpec.describe Backups::RestoreDatabaseBackupService do
  def gzip(sql)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) { |gz| gz.write(sql) }
    io.string
  end

  def backup_with_archive(sql:, checksum: nil)
    archive_bytes = gzip(sql)
    backup = create(:system_database_backup, checksum_sha256: checksum || Digest::SHA256.hexdigest(archive_bytes))
    backup.archive.attach(io: StringIO.new(archive_bytes), filename: 'backup.sql.gz', content_type: 'application/gzip')
    backup
  end

  def isolated_target_url
    'postgres://user:pw@isolated-host:5432/restore_target'
  end

  it 'refuses to run inside a production process, before touching the archive at all' do
    backup = backup_with_archive(sql: '-- noop')
    allow(Rails.env).to receive(:production?).and_return(true)

    expect { described_class.call(backup:, target_database_url: isolated_target_url) }
      .to raise_error(Backups::PermanentBackupError, /production/)
  end

  it 'refuses to run without an explicit target_database_url' do
    backup = backup_with_archive(sql: '-- noop')

    expect { described_class.call(backup:, target_database_url: nil) }
      .to raise_error(Backups::PermanentBackupError, /target_database_url/)
  end

  it 'refuses a target that is not a postgres:// URL' do
    backup = backup_with_archive(sql: '-- noop')

    expect { described_class.call(backup:, target_database_url: 'not-a-url') }
      .to raise_error(Backups::PermanentBackupError, /Invalid target_database_url/)
  end

  it "refuses a target that resolves to this process's own configured database" do
    current = ActiveRecord::Base.connection_db_config.configuration_hash
    host = current.fetch(:host, 'localhost')
    port = current.fetch(:port, 5432)
    own_url = "postgres://#{current.fetch(:username)}@#{host}:#{port}/#{current.fetch(:database)}"
    backup = backup_with_archive(sql: '-- noop')

    expect { described_class.call(backup:, target_database_url: own_url) }
      .to raise_error(Backups::PermanentBackupError, /own configured database/)
  end

  it 'refuses to restore when the downloaded archive checksum does not match the recorded checksum' do
    backup = backup_with_archive(sql: '-- noop', checksum: 'a' * 64)

    expect { described_class.call(backup:, target_database_url: isolated_target_url) }
      .to raise_error(Backups::PermanentBackupError, /[Cc]hecksum/)
  end

  it 'refuses to restore when the archive is not valid gzip data' do
    backup = create(:system_database_backup, checksum_sha256: Digest::SHA256.hexdigest('not gzip'))
    backup.archive.attach(io: StringIO.new('not gzip'), filename: 'backup.sql.gz', content_type: 'application/gzip')

    expect { described_class.call(backup:, target_database_url: isolated_target_url) }
      .to raise_error(Backups::PermanentBackupError, /gzip/)
  end

  it 'raises PermanentBackupError when psql fails' do
    backup = backup_with_archive(sql: '-- fake sql dump')
    allow(Open3).to receive(:capture3).and_return(['', 'syntax error',
                                                   instance_double(Process::Status, success?: false)])

    expect { described_class.call(backup:, target_database_url: isolated_target_url) }
      .to raise_error(Backups::PermanentBackupError, /psql restore failed/)
  end

  it 'streams the archive to disk rather than loading it into memory via ActiveStorage#download' do
    backup = backup_with_archive(sql: '-- fake sql dump')
    allow(Open3).to receive(:capture3).and_return(['', '', instance_double(Process::Status, success?: true)])
    allow(backup.archive).to receive(:download).and_call_original

    described_class.call(backup:, target_database_url: isolated_target_url)

    # ActiveStorage's #download only accepts a block in the streaming form;
    # calling it with none loads the whole blob into memory as a String.
    expect(backup.archive).to have_received(:download) { |*_args, &block| expect(block).to be_present }
  end

  describe 'real PostgreSQL round trip', :real_postgres do
    def target_database_name
      'descon_test_restore_dr_drill'
    end

    def maintenance_connection
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      PG.connect(host: config.fetch(:host, 'localhost'), port: config.fetch(:port, 5432),
                 user: config.fetch(:username), password: config[:password], dbname: 'postgres')
    end

    def target_connection
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      PG.connect(host: config.fetch(:host, 'localhost'), port: config.fetch(:port, 5432),
                 user: config.fetch(:username), password: config[:password], dbname: target_database_name)
    end

    def target_database_url
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      host = config.fetch(:host, 'localhost')
      port = config.fetch(:port, 5432)
      "postgres://#{config.fetch(:username)}@#{host}:#{port}/#{target_database_name}"
    end

    before do
      conn = maintenance_connection
      conn.exec("DROP DATABASE IF EXISTS #{target_database_name}")
      conn.exec("CREATE DATABASE #{target_database_name}")
    ensure
      conn&.close
    end

    after do
      conn = maintenance_connection
      conn.exec("DROP DATABASE IF EXISTS #{target_database_name}")
    ensure
      conn&.close
    end

    it 'restores a real gzip-compressed SQL dump into the isolated target database' do
      dump_sql = <<~SQL.squish
        DROP TABLE IF EXISTS dr_drill_widgets;
        CREATE TABLE dr_drill_widgets (id integer PRIMARY KEY, name text NOT NULL);
        INSERT INTO dr_drill_widgets (id, name) VALUES (1, 'widget-one'), (2, 'widget-two');
      SQL
      backup = backup_with_archive(sql: dump_sql)

      described_class.call(backup:, target_database_url: target_database_url)

      conn = target_connection
      result = conn.exec('SELECT id, name FROM dr_drill_widgets ORDER BY id')
      expect(result.to_a).to eq(
        [{ 'id' => '1', 'name' => 'widget-one' }, { 'id' => '2', 'name' => 'widget-two' }]
      )
    ensure
      conn&.close
    end

    it 'cleanly re-restores into a non-empty target thanks to --clean --if-exists in the dump itself' do
      dump_sql = <<~SQL.squish
        DROP TABLE IF EXISTS dr_drill_widgets;
        CREATE TABLE dr_drill_widgets (id integer PRIMARY KEY, name text NOT NULL);
        INSERT INTO dr_drill_widgets (id, name) VALUES (1, 'widget-one');
      SQL
      backup = backup_with_archive(sql: dump_sql)

      described_class.call(backup:, target_database_url: target_database_url)
      expect { described_class.call(backup:, target_database_url: target_database_url) }.not_to raise_error

      conn = target_connection
      result = conn.exec('SELECT count(*) AS count FROM dr_drill_widgets')
      expect(result.first.fetch('count')).to eq('1')
    ensure
      conn&.close
    end
  end
end
