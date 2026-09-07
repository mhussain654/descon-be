# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Read-only browsing of database backup history (MPS-903). Deliberately index-only --
      # no show/update/destroy: a backup record's outcome is written only by the owning job,
      # never through an application API, matching how AuditEvent is handled.
      class SystemDatabaseBackupsController < ProtectedStaffController
        # Returns a paginated, most-recent-first list of database backup attempts.
        def index
          authorize ::SystemDatabaseBackup

          query = ::Admin::SystemDatabaseBackups::IndexQuery.new(scope: backup_scope, params:)
          backups = query.call

          render_collection(
            data: backups.map { |backup| ::Admin::SystemDatabaseBackupSerializer.new(backup).as_json },
            pagination: query.pagination
          )
        end

        private

        def backup_scope
          policy_scope(::SystemDatabaseBackup)
        end
      end
    end
  end
end
