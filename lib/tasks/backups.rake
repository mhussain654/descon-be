# frozen_string_literal: true

namespace :backups do
  desc 'Restore a database backup (by its public_id) into the currently configured DATABASE_URL. ' \
       'Intended for a disaster-recovery drill against an isolated database -- never run against ' \
       'a database anyone still depends on, since pg_restore --clean drops existing objects first.'
  task :restore, [:public_id] => :environment do |_task, args|
    public_id = args[:public_id]
    abort('Usage: bin/rails "backups:restore[<public_id>]"') if public_id.blank?

    backup = SystemDatabaseBackup.find_by(public_id:)
    abort("No backup found with public_id #{public_id}") if backup.blank?
    abort("Backup #{public_id} has no archive attached (status: #{backup.status_code})") unless backup.archive.attached?

    Backups::RestoreDatabaseBackupService.call(backup:)
    puts "Restored backup #{public_id} (taken at #{backup.taken_at.utc.iso8601})."
  end
end
