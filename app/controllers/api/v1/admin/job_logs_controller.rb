# frozen_string_literal: true

module Api
  module V1
    module Admin
      # Developer-only, read-only view of background job runs recorded by Solid
      # Queue (pending, scheduled, running, finished and failed), with the
      # error for failed runs, so failures can be read without the Rails
      # console. Index only: nothing here retries, discards or edits a job.
      class JobLogsController < ProtectedStaffController
        def index
          authorize ::SolidQueue::Job, policy_class: ::Admin::JobLogPolicy

          job_classes = ::Admin::JobLogs::JobClassCatalog.call
          query = ::Admin::JobLogs::IndexQuery.new(scope: job_scope, params:, job_classes:)
          rows = query.call

          render_collection(
            data: rows.map { |row| ::Admin::JobLogs::JobLogSerializer.new(row).as_json },
            pagination: query.pagination,
            meta: { applied_filters: query.applied_filters, job_classes:, statuses: ::Admin::JobLogs::IndexQuery::STATUSES }
          )
        end

        private

        def job_scope
          policy_scope(::SolidQueue::Job, policy_scope_class: ::Admin::JobLogPolicy::Scope)
        end
      end
    end
  end
end
