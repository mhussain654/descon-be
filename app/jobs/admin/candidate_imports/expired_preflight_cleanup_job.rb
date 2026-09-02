# frozen_string_literal: true

module Admin
  module CandidateImports
    class ExpiredPreflightCleanupJob < ApplicationJob
      queue_as :low_priority

      def perform
        ::Admin::Candidates::Imports::ExpiredPreflightCleanupService.call
      end
    end
  end
end
