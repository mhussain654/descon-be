# frozen_string_literal: true

module Admin
  module JobLogs
    # One background job run on the developer-only Job logs page. The job's
    # arguments are never included (they can carry personal data); the error
    # message is redacted with the same rules as Sentry and truncated, and the
    # backtrace is cut to its first lines with the server paths removed.
    class JobLogSerializer
      MESSAGE_LIMIT = 1_000
      BACKTRACE_LINES = 15
      BACKTRACE_LINE_LIMIT = 300
      APP_ROOT_PREFIX = "#{Rails.root.to_s.chomp('/')}/".freeze # rubocop:disable Rails/FilePath

      def initialize(row)
        @row = row
        @job = row.job
      end

      def as_json(*)
        job_fields.merge(run_fields, error: serialized_error)
      end

      private

      def job_fields
        { id: @job.id, active_job_id: @job.active_job_id, job_class: @job.class_name,
          queue_name: @job.queue_name, priority: @job.priority }
      end

      def run_fields
        { status: @row.status, attempt: @row.attempt, enqueued_at: iso(@job.created_at),
          scheduled_at: iso(@job.scheduled_at), started_at: iso(@row.started_at),
          finished_at: iso(@job.finished_at), failed_at: iso(@row.failed_at) }
      end

      def iso(time) = time&.utc&.iso8601

      def serialized_error
        error = @row.error
        return nil unless error.is_a?(Hash)

        {
          exception_class: error['exception_class'].to_s.truncate(200),
          message: redact(error['message']).truncate(MESSAGE_LIMIT),
          backtrace: Array(error['backtrace']).first(BACKTRACE_LINES).map { |line| clean_line(line) }
        }
      end

      def redact(text)
        ::Observability::SentryRedaction.redact_text(text.to_s)
      end

      def clean_line(line)
        cleaned = line.to_s.delete_prefix(APP_ROOT_PREFIX)
        Gem.path.each { |gem_path| cleaned = cleaned.sub("#{gem_path}/gems/", '') }
        redact(cleaned).truncate(BACKTRACE_LINE_LIMIT)
      end
    end
  end
end
