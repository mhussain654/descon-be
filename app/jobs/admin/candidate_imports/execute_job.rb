# frozen_string_literal: true

module Admin
  module CandidateImports
    class ExecuteJob < ApplicationJob
      queue_as :candidate_imports

      retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: 10.seconds, attempts: 3

      def perform(import_id, request_id)
        ::Admin::Candidates::Imports::BatchExecutionService.call(import_id:, request_id:)
      rescue StandardError
        ::Admin::Candidates::Imports::BatchExecutionService.record_failure(import_id:, request_id:)
        raise
      end
    end
  end
end
