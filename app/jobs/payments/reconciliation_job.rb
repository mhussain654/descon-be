# frozen_string_literal: true

module Payments
  class ReconciliationJob < ApplicationJob
    queue_as :default

    def perform(run_date = Date.current.iso8601)
      Payments::ReconciliationService.call(run_date: Date.iso8601(run_date))
    end
  end
end
