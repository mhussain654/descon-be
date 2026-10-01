# frozen_string_literal: true

module AiCalls
  # Resolves a needs_manual_review CandidateAiCall: an admin selects the
  # outcome the call actually had (having listened to the recording/read the
  # transcript) and the header row is updated to reflect it, alongside an
  # immutable CandidateAiCallEvent recording who decided what and why (see
  # the plan's "Manual-review resolution"). Without this, a call routed to
  # manual review had no way to ever leave that state.
  #
  # Locks the row and re-checks `needs_manual_review?` under that lock, so
  # two concurrent resolution attempts (or a second attempt after the call
  # was already resolved) can't both succeed -- the second sees the
  # already-resolved state and raises.
  class ResolveManualReviewService < ApplicationService
    # rubocop:disable Metrics/ParameterLists
    def initialize(candidate_ai_call:, actor:, outcome:, request_id:, outcome_reason: nil, notes: nil)
      # rubocop:enable Metrics/ParameterLists
      @candidate_ai_call = candidate_ai_call
      @actor = actor
      @outcome = outcome
      @outcome_reason = outcome_reason
      @notes = notes
      @request_id = request_id
    end

    def call
      CandidateAiCall.transaction do
        call_record = CandidateAiCall.lock.find(@candidate_ai_call.id)
        raise AiCallNotAwaitingReviewError unless call_record.needs_manual_review?

        previous_outcome = call_record.outcome
        apply_resolution!(call_record)
        record_event!(call_record, previous_outcome:)
        call_record
      end
    end

    private

    def apply_resolution!(call_record)
      call_record.update!(
        outcome: @outcome, outcome_reason: @outcome_reason.presence || call_record.outcome_reason,
        reviewed_by: @actor, reviewed_at: Time.current, review_resolution: @outcome, review_notes: @notes
      )
    end

    def record_event!(call_record, previous_outcome:)
      call_record.candidate_ai_call_events.create!(
        actor: @actor, provider_code: call_record.provider_code, event_source: 'admin_review',
        event_type: 'manual_outcome_resolved', event_key: "manual_review_resolved:#{call_record.id}",
        occurred_at: Time.current, request_id: @request_id,
        payload: { previous_outcome:, selected_outcome: @outcome, reason: @notes }.compact
      )
    end
  end
end
