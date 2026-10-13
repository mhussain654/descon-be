# frozen_string_literal: true

module Deployment
  # Reports whether Solid Queue's processes are alive right now, from their
  # database heartbeats -- run after a release is live
  # (`bin/rails deployment:queue_status`), because unlike Deployment::PreflightCheck
  # it needs the new code's service to be running. A worker and a dispatcher
  # must both be present for queued jobs to execute; the scheduler is what
  # fires config/recurring.yml entries (including the nightly database backup).
  class QueueStatusCheck < ApplicationService
    HEARTBEAT_WINDOW = 2.minutes
    REQUIRED_KINDS = %w[Worker Dispatcher].freeze

    def call
      alive = SolidQueue::Process.where(last_heartbeat_at: HEARTBEAT_WINDOW.ago..).group(:kind).count
      missing = REQUIRED_KINDS - alive.keys
      detail = alive.empty? ? 'no live Solid Queue processes' : alive.sort.map { |kind, n| "#{kind} x#{n}" }.join(', ')
      if missing.any?
        return CheckResult.new(name: 'solid queue', status: :fail,
                               detail: "#{detail}; missing #{missing.join(', ')}")
      end

      CheckResult.new(name: 'solid queue', status: :pass, detail:)
    end
  end
end
