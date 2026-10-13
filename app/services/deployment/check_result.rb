# frozen_string_literal: true

module Deployment
  # One line of a deployment readiness report (see Deployment::PreflightCheck).
  # `detail` is human-readable and must never contain a credential value --
  # only whether one is present.
  class CheckResult
    STATUSES = %i[pass warn fail].freeze

    attr_reader :name, :status, :detail

    def initialize(name:, status:, detail:)
      raise ArgumentError, "unknown status #{status.inspect}" unless STATUSES.include?(status)

      @name = name
      @status = status
      @detail = detail
    end

    def failed? = status == :fail

    def to_s = "[#{status.to_s.upcase}] #{name}: #{detail}"
  end
end
