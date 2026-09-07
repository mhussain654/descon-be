# frozen_string_literal: true

module Backups
  # A backup step failed for a reason worth retrying (e.g. a momentary S3 upload hiccup) --
  # distinct from PermanentBackupError, which marks that day's attempt failed outright.
  class TransientBackupError < StandardError; end
end
