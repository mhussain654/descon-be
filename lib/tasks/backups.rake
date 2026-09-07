# frozen_string_literal: true

namespace :backups do
  desc 'Restore a database backup (by its public_id) into an explicit, isolated target database ' \
       '(RESTORE_TARGET_DATABASE_URL env var -- never the currently configured DATABASE_URL). ' \
       'Intended for a disaster-recovery drill against a throwaway database -- the dump carries ' \
       '--clean --if-exists, so restoring drops and recreates existing objects in the *target*, ' \
       'never anywhere else. Refuses to run in production.'
  task :restore, [:public_id] => :environment do |_task, args|
    public_id = args[:public_id]
    abort('Usage: bin/rails "backups:restore[<public_id>]"') if public_id.blank?

    target_database_url = ENV.fetch('RESTORE_TARGET_DATABASE_URL', nil)
    if target_database_url.blank?
      abort('RESTORE_TARGET_DATABASE_URL must be set to an isolated postgres:// connection string -- ' \
            'this task never restores into the database this Rails process is itself configured for.')
    end

    backup = SystemDatabaseBackup.find_by(public_id:)
    abort("No backup found with public_id #{public_id}") if backup.blank?
    abort("Backup #{public_id} has no archive attached (status: #{backup.status_code})") unless backup.archive.attached?

    Backups::RestoreDatabaseBackupService.call(backup:, target_database_url:)
    target_host = target_database_url.split('@').last
    puts "Restored backup #{public_id} (taken at #{backup.taken_at.utc.iso8601}) into #{target_host}."
  end
end
