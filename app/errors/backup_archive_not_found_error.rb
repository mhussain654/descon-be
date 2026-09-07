# frozen_string_literal: true

class BackupArchiveNotFoundError < BaseError
  def initialize(message: nil)
    message ||= I18n.t('api.errors.backup_archive_not_found')
    super(code: 'backup_archive_not_found', message:, status: :unprocessable_content)
  end
end
