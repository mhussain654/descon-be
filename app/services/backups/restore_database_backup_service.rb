# frozen_string_literal: true

require 'open3'
require 'zlib'
require 'digest'
require 'uri'

module Backups
  # Downloads a SystemDatabaseBackup's archive and restores it into an
  # explicitly-named, isolated target database via psql (the dump is
  # plain-format SQL, produced by Backups::CreateDatabaseBackupJob's
  # `pg_dump --format=plain --clean --if-exists`). This is the tool a DR
  # drill runs against a throwaway database -- it refuses to run at all
  # inside a production process, refuses to run without an explicit target
  # connection string, and verifies the downloaded archive's checksum before
  # ever handing it to psql.
  #
  # "Explicit isolated target" is enforced by *requiring* a target
  # connection string (never falling back to the app's own configured
  # database) and refusing if that target happens to resolve to the same
  # host/port/database this Rails process is itself connected to.
  class RestoreDatabaseBackupService < ApplicationService
    def initialize(backup:, target_database_url:)
      @backup = backup
      @target_database_url = target_database_url
    end

    def call
      refuse_in_production!
      target = parse_and_guard_target!

      Tempfile.create(['descon_db_restore', '.sql.gz']) do |archive_file|
        archive_file.binmode
        stream_archive_to!(archive_file)
        archive_file.flush
        verify_checksum!(archive_file.path)

        restore_from_archive!(archive_file.path, target)
      end
    end

    # Parses a postgres:// connection URL into the pieces psql/PGPASSWORD need.
    TargetDatabase = Struct.new(:host, :port, :username, :password, :database) do
      def self.parse(url)
        uri = URI.parse(url)
        return nil unless %w[postgres postgresql].include?(uri.scheme)
        return nil if uri.host.blank? || uri.path.blank?

        new(uri.host, uri.port || 5432, uri.user, uri.password, uri.path.delete_prefix('/'))
      rescue URI::Error
        nil
      end
    end

    private

    def refuse_in_production!
      return unless Rails.env.production?

      raise Backups::PermanentBackupError, 'Refusing to restore a backup from inside a production process'
    end

    def restore_from_archive!(archive_path, target)
      Tempfile.create(['descon_db_restore', '.sql']) do |sql_file|
        sql_file.binmode
        decompress!(archive_path, sql_file.path)
        sql_file.close

        run_psql!(sql_file.path, target)
      end
    end

    def parse_and_guard_target!
      if @target_database_url.blank?
        raise Backups::PermanentBackupError, 'A target_database_url is required to restore into'
      end

      target = TargetDatabase.parse(@target_database_url)
      raise Backups::PermanentBackupError, "Invalid target_database_url: #{@target_database_url}" if target.blank?

      refuse_own_database!(target)
      target
    end

    def refuse_own_database!(target)
      return unless same_as_current_database?(target)

      raise Backups::PermanentBackupError, "Refusing to restore into this process's own configured database"
    end

    def same_as_current_database?(target)
      current = ActiveRecord::Base.connection_db_config.configuration_hash
      target.host.to_s == current.fetch(:host, 'localhost').to_s &&
        target.port.to_i == current.fetch(:port, 5432).to_i &&
        target.database == current.fetch(:database).to_s
    end

    # Streams the ActiveStorage blob to disk in bounded chunks -- never
    # loading the whole (potentially multi-gigabyte, for a production-sized
    # database) compressed archive into memory at once the way
    # `blob.download` (no block) would.
    def stream_archive_to!(file)
      @backup.archive.download { |chunk| file.write(chunk) }
    end

    def verify_checksum!(archive_path)
      expected = @backup.checksum_sha256
      return if expected.blank? # older backups predating checksum capture -- nothing to compare against

      actual = Digest::SHA256.file(archive_path).hexdigest
      return if ActiveSupport::SecurityUtils.secure_compare(actual, expected)

      raise Backups::PermanentBackupError,
            'Downloaded archive checksum does not match the recorded checksum -- refusing to restore'
    end

    def decompress!(archive_path, sql_path)
      File.open(archive_path, 'rb') do |input|
        Zlib::GzipReader.wrap(input) do |gz|
          File.open(sql_path, 'wb') { |output| IO.copy_stream(gz, output) }
        end
      end
    rescue Zlib::Error => e
      raise Backups::PermanentBackupError, "Archive is not valid gzip data: #{e.message}"
    end

    def run_psql!(sql_path, target)
      _stdout, stderr, status = Open3.capture3({ 'PGPASSWORD' => target.password.to_s }, *psql_argv(target, sql_path))
      raise Backups::PermanentBackupError, "psql restore failed: #{stderr.lines.first}" unless status.success?
    end

    def psql_argv(target, sql_path)
      [
        'psql',
        '--host', target.host.to_s,
        '--port', target.port.to_s,
        '--username', target.username.to_s,
        '--dbname', target.database.to_s,
        '--file', sql_path,
        '--set', 'ON_ERROR_STOP=1'
      ]
    end
  end
end
