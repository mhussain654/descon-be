# frozen_string_literal: true

module Admin
  module JobLogs
    # Works out the status, attempt and failure of a page of Solid Queue jobs
    # with one query per execution table for the whole page (no per-row
    # lookups).
    class RowBuilder
      Row = Struct.new(:job, :status, :attempt, :started_at, :failed_at, :error, keyword_init: true)

      def initialize(jobs)
        @jobs = jobs
        ids = jobs.map(&:id)
        @failed = ::SolidQueue::FailedExecution.where(job_id: ids).select(:job_id, :error, :created_at)
                                               .index_by(&:job_id)
        @claimed = ::SolidQueue::ClaimedExecution.where(job_id: ids).pluck(:job_id, :created_at).to_h
        @scheduled = ::SolidQueue::ScheduledExecution.where(job_id: ids).pluck(:job_id).to_set
      end

      def call
        @jobs.map do |job|
          failure = @failed[job.id]
          Row.new(job:, status: status_for(job), attempt: attempt_for(job), started_at: @claimed[job.id],
                  failed_at: failure&.created_at, error: failure&.error)
        end
      end

      private

      def status_for(job)
        return 'finished' if job.finished_at.present?
        return 'failed' if @failed.key?(job.id)
        return 'running' if @claimed.key?(job.id)
        return 'scheduled' if @scheduled.include?(job.id)

        'pending'
      end

      # Active Job stores how many times the job had already run when it was
      # enqueued; a retry is enqueued again with the count raised. Only that
      # number is read from the arguments, which are never returned.
      def attempt_for(job)
        executions = job.arguments.is_a?(Hash) ? job.arguments['executions'] : nil
        executions.is_a?(Integer) ? executions + 1 : nil
      end
    end
  end
end
