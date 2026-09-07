# frozen_string_literal: true

require 'open3'
require 'zlib'

module Backups
  # Downloads a SystemDatabaseBackup's archive and restores it into whatever DATABASE_URL is
  # currently configured, via psql (the dump is plain-format SQL, produced by
  # Backups::CreateDatabaseBackupJob's `pg_dump --format=plain`). This is the tool a DR drill
  # runs against an isolated/throwaway database -- it does not itself decide when to run a
  # drill or verify the target is actually isolated; that is an operational responsibility of
  # whoever invokes `bin/rails backups:restore`, documented in the DR runbook.
  class RestoreDatabaseBackupService < ApplicationService
    def initialize(backup:)
      @backup = backup
    end

    def call
      Tempfile.create(['descon_db_restore', '.sql']) do |sql_file|
        sql_file.binmode
        Zlib::GzipReader.wrap(StringIO.new(@backup.archive.download)) { |gz| IO.copy_stream(gz, sql_file) }
        sql_file.close

        run_psql!(sql_file.path)
      end
    end

    private

    def run_psql!(sql_path)
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      _stdout, stderr, status = Open3.capture3({ 'PGPASSWORD' => config[:password].to_s }, *psql_argv(config, sql_path))
      raise Backups::PermanentBackupError, "psql restore failed: #{stderr.lines.first}" unless status.success?
    end

    def psql_argv(config, sql_path)
      [
        'psql',
        '--host', config.fetch(:host, 'localhost').to_s,
        '--port', config.fetch(:port, 5432).to_s,
        '--username', config.fetch(:username).to_s,
        '--dbname', config.fetch(:database).to_s,
        '--file', sql_path,
        '--set', 'ON_ERROR_STOP=1'
      ]
    end
  end
end
