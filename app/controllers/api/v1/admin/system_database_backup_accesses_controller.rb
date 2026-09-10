# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Lets an authorized staff member record and retrieve a short-lived download URL for a
      # database backup archive (MPS-903).
      class SystemDatabaseBackupAccessesController < ProtectedStaffController
        # Records that this staff member accessed this backup and returns the access details.
        def create
          authorize backup, :access?, policy_class: ::SystemDatabaseBackupPolicy

          response.set_header('Cache-Control', 'no-store, private')
          render_success(
            data: ::Admin::SystemDatabaseBackupAccessSerializer.new(access_result).as_json,
            status: :created
          )
        end

        private

        def access_result
          @access_result ||= ::Admin::SystemDatabaseBackups::AccessService.call(
            actor: current_user,
            backup:,
            request_id: request.request_id
          )
        end

        def backup
          @backup ||= ::SystemDatabaseBackup.find_by!(public_id: params.expect(:system_database_backup_id))
        end
      end
    end
  end
end
