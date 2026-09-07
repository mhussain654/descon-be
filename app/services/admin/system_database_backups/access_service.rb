# frozen_string_literal: true

module Admin
  module SystemDatabaseBackups
    # Issues a short-lived signed download URL for a database backup archive (MPS-903),
    # mirroring CandidateWorkflows::FlightTicketAccessService's signed-URL + audit-event
    # pattern exactly. Downloading a full database backup is itself a security-sensitive
    # action, so every access is audited the same way any other sensitive file access is.
    class AccessService < ApplicationService
      ACCESS_TTL = ENV.fetch('ADMIN_DOCUMENT_ACCESS_TTL_SECONDS', 300).to_i.seconds

      AccessResult = Data.define(:backup, :expires_at, :url)

      def initialize(actor:, backup:, request_id:)
        @actor = actor
        @backup = backup
        @request_id = request_id
      end

      def call
        raise BackupArchiveNotFoundError unless @backup.archive.attached?

        expires_at = Time.current + ACCESS_TTL
        url = access_url(expires_at:)
        create_audit_event!(expires_at:)

        AccessResult.new(backup: @backup, expires_at: expires_at.utc.iso8601, url:)
      end

      private

      def access_url(expires_at:)
        Rails.application.routes.url_helpers.rails_service_blob_proxy_path(
          @backup.archive.blob.signed_id(expires_at:),
          @backup.archive.blob.filename,
          disposition: 'attachment',
          only_path: true
        )
      end

      def create_audit_event!(expires_at:)
        AuditEvent.create!(audit_attributes(expires_at:))
      end

      def audit_attributes(expires_at:)
        {
          actor: @actor,
          entity_type: 'SystemDatabaseBackup',
          entity_id: @backup.id,
          action_code: 'system_database_backup_accessed',
          request_id: @request_id,
          metadata: audit_metadata(expires_at:),
          occurred_at: Time.current
        }
      end

      def audit_metadata(expires_at:)
        {
          actor_public_id: @actor.public_id,
          backup_public_id: @backup.public_id,
          expires_at: expires_at.utc.iso8601
        }
      end
    end
  end
end
