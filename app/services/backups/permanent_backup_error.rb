# frozen_string_literal: true

module Backups
  # pg_dump itself failed (bad config, disk full, etc.) -- not worth retrying automatically;
  # marks that day's attempt failed and waits for the next scheduled run.
  class PermanentBackupError < StandardError; end
end
