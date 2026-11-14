# frozen_string_literal: true

module Backups
  # Runs daily (config/recurring.yml) and deletes database backups that are no
  # longer needed, together with their archive in S3, so the bucket does not
  # grow by one full dump every day. Every backup is a complete copy, but older
  # copies are kept for data damage that is only noticed later:
  #
  # * the 14 newest successful backups (two weeks of daily backups);
  # * the first successful backup of each of the last 6 calendar months
  #   (this month included);
  # * failed or unfinished attempts (which hold no usable archive) for 30 days.
  #
  # Everything else is deleted. The S3 file is removed first; if that fails the
  # row stays and the next run tries again, so the Backups page never lists a
  # backup whose file is gone. Each deletion is recorded as an AuditEvent.
  class PruneDatabaseBackupsJob < ApplicationJob
    queue_as :default

    DAILY_BACKUPS_KEPT = 14
    MONTHLY_BACKUPS_KEPT = 6
    UNSUCCESSFUL_KEPT_FOR = 30.days

    def perform
      prunable_backups.each { |backup| prune!(backup) }
    end

    private

    def prunable_backups
      kept_ids = daily_ids + monthly_ids
      succeeded = SystemDatabaseBackup.succeeded.where.not(id: kept_ids)
      unsuccessful = SystemDatabaseBackup.where.not(status_code: 'succeeded')
                                         .where(taken_at: ...UNSUCCESSFUL_KEPT_FOR.ago)
      succeeded.or(unsuccessful).with_attached_archive.order(:taken_at).to_a
    end

    def daily_ids
      SystemDatabaseBackup.succeeded.order(taken_at: :desc, id: :desc).limit(DAILY_BACKUPS_KEPT).pluck(:id)
    end

    def monthly_ids
      first_month = Time.current.beginning_of_month - (MONTHLY_BACKUPS_KEPT - 1).months
      SystemDatabaseBackup.succeeded.where(taken_at: first_month..)
                          .order(:taken_at, :id).pluck(:id, :taken_at)
                          .group_by { |_id, taken_at| taken_at.beginning_of_month }
                          .map { |_month, rows| rows.first.first }
    end

    def prune!(backup)
      backup.archive.purge if backup.archive.attached?
      SystemDatabaseBackup.transaction do
        backup.destroy!
        record_audit!(backup)
      end
    end

    def record_audit!(backup)
      ::AuditEvent.create!(
        actor: nil, entity_type: 'SystemDatabaseBackup', entity_id: backup.id,
        action_code: 'system_database_backup_pruned', request_id: "backup-prune-#{backup.public_id}",
        occurred_at: Time.current,
        metadata: { backup_public_id: backup.public_id, status_code: backup.status_code,
                    taken_at: backup.taken_at.utc.iso8601, byte_size: backup.byte_size }
      )
    end
  end
end
