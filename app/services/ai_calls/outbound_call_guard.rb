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

    # Applies to every outbound call regardless of trigger path -- a shared,
    # account-wide budget across admin-triggered and workflow-stage-
    # triggered calls alike.
    def ensure_daily_limit_not_reached!
      raise AiCallDailyLimitReachedError if daily_limit_reached?
    end

    # A bulk batch must fit in what is left of today's account-wide budget;
    # refused up front rather than failing halfway through.
    def ensure_capacity_for!(count)
      raise AiCallDailyLimitReachedError if remaining_daily_capacity < count
    end

    def remaining_daily_capacity
      [@configuration.daily_outbound_call_limit - calls_placed_today, 0].max
    end

    # Time-windowed, per-(assignment, call_reason) cooldown -- meaningful
    # only for the admin-triggered flow. A call with a voice is counted per
    # voice, so a different call type can be placed straight away. The
    # workflow-stage-triggered flow enforces its own, stronger, permanent
    # per-stage dedup instead (every stage-triggered call shares one
    # call_reason, so this cooldown would otherwise block a genuinely
    # different stage's call). Call inside the caller's transaction, after
    # acquiring the per-candidate+reason advisory lock, so a concurrent
    # trigger can't race past this.
    def ensure_cooldown_elapsed!(candidate_assignment:, call_reason:, voice_id: nil)
      raise AiCallTriggerCooldownError if within_cooldown?(candidate_assignment:, call_reason:, voice_id:)
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
      calls_placed_today >= @configuration.daily_outbound_call_limit
    end

    def calls_placed_today
      CandidateAiCall.outbound.where(created_at: Time.current.beginning_of_day..).count
    end

    def within_cooldown?(candidate_assignment:, call_reason:, voice_id:)
      window = @configuration.outbound_trigger_cooldown_minutes.minutes.ago
      recent = CandidateAiCall.outbound.where(candidate_assignment_id: candidate_assignment.id, call_reason:,
                                              created_at: window..)
      recent = recent.where(provider_voice_id: voice_id) if voice_id.present?
      recent.exists?
    end
  end
end
