# frozen_string_literal: true

module AiCalls
  # Raised when AiCalls::AgentConfigSync refuses to push a config change --
  # an internal/rake-task-level safety error, not an API-facing BaseError
  # (mirrors Backups::PermanentBackupError, used the same way by
  # Backups::RestoreDatabaseBackupService#refuse_in_production!).
  class AgentConfigSyncError < StandardError; end
end
