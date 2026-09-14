# frozen_string_literal: true

module AiCalls
  # Single source of truth for mapping a finished call's telephony result and
  # structured post-call extraction onto CandidateAiCall#outcome/outcome_reason
  # (see the plan's outcome-mapping table). Called from the post-call webhook
  # handler and the reconciliation job -- never computed inline elsewhere.
  #
  # `telephony_outcome` is a normalized value the caller derives from the raw
  # Twilio/ElevenLabs status strings before calling this mapper (this class
  # owns the outcome TABLE, not provider-specific status parsing):
  # 'answered' | 'busy' | 'no_answer' | 'voicemail' | 'provider_failure'.
  #
  # `extraction` (only consulted when `telephony_outcome == 'answered'`) is the
  # structured post-call extraction hash: {human_answered:, callback_requested:,
  # escalation_requested:, call_resolved:} (string or symbol keys). Missing,
  # malformed, or self-contradictory extraction (e.g. telephony says answered
  # but the extraction says the human never answered) maps to
  # outcome: nil, outcome_reason: 'needs_manual_review' -- reserved for
  # genuinely bad/missing data, never used merely because an issue went
  # unresolved (that's outcome: 'answered', outcome_reason: 'unresolved').
  module OutcomeMapper
    Result = Struct.new(:outcome, :outcome_reason, keyword_init: true)

    NOT_ANSWERED_REASONS = %w[busy no_answer voicemail provider_failure].freeze
    MANUAL_REVIEW = Result.new(outcome: nil, outcome_reason: 'needs_manual_review').freeze

    def self.call(telephony_outcome:, extraction: nil)
      return Result.new(outcome: 'not_answered', outcome_reason: telephony_outcome) if
        NOT_ANSWERED_REASONS.include?(telephony_outcome)

      return MANUAL_REVIEW unless telephony_outcome == 'answered'

      map_answered_call(extraction)
    end

    def self.map_answered_call(extraction)
      facts = normalized_extraction(extraction)
      return MANUAL_REVIEW if facts.blank?

      return Result.new(outcome: 'callback_required', outcome_reason: 'candidate_requested') if
        facts.fetch(:callback_requested)
      return Result.new(outcome: 'callback_required', outcome_reason: 'agent_escalation') if
        facts.fetch(:escalation_requested)

      resolved_call_result(facts)
    end
    private_class_method :map_answered_call

    def self.resolved_call_result(facts)
      case facts.fetch(:call_resolved)
      when true then Result.new(outcome: 'answered', outcome_reason: 'resolved')
      when false then Result.new(outcome: 'answered', outcome_reason: 'unresolved')
      else MANUAL_REVIEW
      end
    end
    private_class_method :resolved_call_result

    # Returns a hash with symbol keys and strict booleans for the fields this
    # mapper reads, or nil if the extraction is missing/malformed/
    # self-contradictory (telephony reported the call as answered, but the
    # extraction says no human ever answered it).
    def self.normalized_extraction(extraction)
      return nil unless extraction.is_a?(Hash)

      data = extraction.symbolize_keys
      return nil unless [true, false].include?(data[:human_answered])
      return nil if data[:human_answered] == false

      {
        callback_requested: data[:callback_requested] == true,
        escalation_requested: data[:escalation_requested] == true,
        call_resolved: data[:call_resolved]
      }
    end
    private_class_method :normalized_extraction
  end
end
