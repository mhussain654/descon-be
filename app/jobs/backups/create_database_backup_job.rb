# frozen_string_literal: true

require 'open3'
require 'zlib'
require 'digest'

module Backups
  # Runs the daily database backup (MPS-903): pg_dump -> gzip -> attach to a
  # SystemDatabaseBackup row via ActiveStorage's already-configured S3
  # service (the same private-attachment mechanism used for every other
  # sensitive file in this app). Scheduled once a day via config/recurring.yml.
  #
  # Deliberately database-only -- documents/bank proofs/flight tickets
  # already live durably in S3 via their own ActiveStorage attachments;
  # re-backing those up here would be pure duplication. Restoring this dump
  # into a fresh database leaves every existing ActiveStorage reference
  # (bucket + key) intact and resolvable exactly as before.
  class CreateDatabaseBackupJob < ApplicationJob
    queue_as :default

    # Only the S3 upload step is worth retrying automatically -- a pg_dump
    # failure (bad config, disk full) marks that day's attempt failed and
    # waits for tomorrow's scheduled run instead.
    retry_on Backups::TransientBackupError, wait: :polynomially_longer, attempts: 3

    def perform(run_date = Date.current.iso8601)
      return if already_backed_up?(run_date)

      backup = SystemDatabaseBackup.create!(status_code: 'in_progress', taken_at: Time.current)
      started_at = monotonic_now

      begin
        dump_and_attach!(backup)
        backup.update!(status_code: 'succeeded', duration_seconds: elapsed(started_at))
      rescue StandardError => e
        backup.update!(status_code: 'failed', duration_seconds: elapsed(started_at), error_message: e.message)
        raise if e.is_a?(Backups::TransientBackupError)
      end
    end

    private

    # Idempotent per calendar day -- guards against a duplicate manual trigger or a misfiring
    # recurring schedule re-running the same day; a prior failed attempt does not block a retry.
    # Note: ActiveJob's retry_on re-runs `perform` from scratch, so a retried attempt creates a
    # second row for the same day rather than resuming the first -- an admin sees both the
    # failed attempt and the eventual success, which is informative, not incorrect.
    def already_backed_up?(run_date)
      day = Date.iso8601(run_date)
      SystemDatabaseBackup.succeeded.exists?(taken_at: day.all_day)
    end

    def dump_and_attach!(backup)
      Tempfile.create(['descon_db_backup', '.sql']) do |dump_file|
        dump_file.close
        run_pg_dump!(dump_file.path)

        Tempfile.create(['descon_db_backup', '.sql.gz']) do |gzip_file|
          gzip_file.close
          gzip!(dump_file.path, gzip_file.path)
          attach!(backup, gzip_file.path)
        end
      end
    end

    # Shells out to pg_dump via an argv array (never an interpolated shell string) so no
    # database config value can be interpreted as a shell command. The password is passed via
    # the PGPASSWORD environment variable, never a command-line argument (which would be
    # visible to other processes via `ps`).
    def run_pg_dump!(dump_path)
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      _stdout, _stderr, status = Open3.capture3({ 'PGPASSWORD' => config[:password].to_s },
                                                *pg_dump_argv(config, dump_path))
      raise Backups::PermanentBackupError, 'pg_dump exited with a non-zero status' unless status.success?
    end

    def pg_dump_argv(config, dump_path)
      [
        'pg_dump', '--no-owner', '--no-privileges', '--format=plain',
        '--host', config.fetch(:host, 'localhost').to_s,
        '--port', config.fetch(:port, 5432).to_s,
        '--username', config.fetch(:username).to_s,
        '--file', dump_path,
        config.fetch(:database).to_s
      ]
    end

    def gzip!(dump_path, gzip_path)
      File.open(dump_path, 'rb') do |input|
        Zlib::GzipWriter.open(gzip_path) { |gz| IO.copy_stream(input, gz) }
      end
    rescue StandardError => e
      raise Backups::PermanentBackupError, "gzip failed: #{e.message}"
    end

    def attach!(backup, gzip_path)
      backup.archive.attach(
        io: File.open(gzip_path),
        filename: "database_backup_#{backup.taken_at.utc.strftime('%Y%m%d_%H%M%S')}.sql.gz",
        content_type: 'application/gzip'
      )
      backup.update!(byte_size: File.size(gzip_path), checksum_sha256: Digest::SHA256.file(gzip_path).hexdigest)
    rescue StandardError => e
      raise Backups::TransientBackupError, e.message
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed(started_at)
      (monotonic_now - started_at).round
    end
  end
end
