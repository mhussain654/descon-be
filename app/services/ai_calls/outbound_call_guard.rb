# frozen_string_literal: true

module AiCalls
  # Encapsulates the outbound-calling operational safety controls (see the
  # plan's "Operational safety controls" section) -- shared by
  # TriggerOutboundCallService (admin-triggered) and the workflow-stage-
  # triggered flow, so these rules are defined once rather than duplicated
  # per trigger path.
  class OutboundCallGuard
    def initialize(configuration: AiCalls::Configuration.new)
      @configuration = configuration
    end

    # Checks that apply before any candidate/assignment is even looked up --
    # global switch, allowed hours, and the triggering admin's own rate limit.
    def ensure_allowed!(actor:)
      raise AiCallOutboundDisabledError unless @configuration.outbound_enabled?
      raise AiCallOutsideCallingHoursError unless within_calling_hours?
      raise AiCallAdminRateLimitedError if admin_rate_limited?(actor)
    end

    # Checks that require a locked candidate_assignment -- call inside the
    # caller's transaction, after acquiring the per-candidate+reason
    # advisory lock, so a concurrent trigger can't race past these.
    def ensure_not_throttled!(candidate_assignment:, call_reason:)
      raise AiCallDailyLimitReachedError if daily_limit_reached?
      raise AiCallTriggerCooldownError if within_cooldown?(candidate_assignment:, call_reason:)
    end

    private

    def within_calling_hours?
      hour = Time.current.in_time_zone('Asia/Karachi').hour
      hour >= @configuration.calling_hours_start && hour < @configuration.calling_hours_end
    end

    def admin_rate_limited?(actor)
      return false if actor.blank?

      CandidateAiCall.outbound.where(triggered_by_id: actor.id, created_at: 1.hour.ago..).count >=
        @configuration.admin_trigger_rate_limit_per_hour
    end

    def daily_limit_reached?
      CandidateAiCall.outbound.where(created_at: Time.current.beginning_of_day..).count >=
        @configuration.daily_outbound_call_limit
    end

    def within_cooldown?(candidate_assignment:, call_reason:)
      window = @configuration.outbound_trigger_cooldown_minutes.minutes.ago
      CandidateAiCall.outbound.exists?(candidate_assignment_id: candidate_assignment.id, call_reason:,
                                       created_at: window..)
    end
  end
end
