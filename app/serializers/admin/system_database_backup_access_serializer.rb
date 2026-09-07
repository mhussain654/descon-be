# frozen_string_literal: true

module Admin
  class SystemDatabaseBackupAccessSerializer
    def initialize(result)
      @result = result
    end

    def as_json(*)
      {
        backup_id: @result.backup.public_id,
        url: @result.url,
        expires_at: @result.expires_at
      }
    end
  end
end
