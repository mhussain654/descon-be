# frozen_string_literal: true

module Admin
  # Read-only view of a SystemDatabaseBackup for the admin backup list (MPS-903). Never
  # includes a direct file URL -- downloading requires the separate, audited access endpoint.
  class SystemDatabaseBackupSerializer
    def initialize(backup)
      @backup = backup
    end

    def as_json(*)
      {
        id: @backup.public_id,
        status: @backup.status_code,
        taken_at: @backup.taken_at.utc.iso8601,
        byte_size: @backup.byte_size,
        checksum_sha256: @backup.checksum_sha256,
        duration_seconds: @backup.duration_seconds,
        error_message: @backup.error_message
      }
    end
  end
end
