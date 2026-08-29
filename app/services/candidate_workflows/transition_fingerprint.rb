# frozen_string_literal: true

module CandidateWorkflows
  class TransitionFingerprint < ApplicationService
    def initialize(candidate_public_id:, transition:)
      @candidate_public_id = candidate_public_id
      @transition = transition
    end

    def call
      Digest::SHA256.hexdigest(fingerprint_payload.to_json)
    end

    private

    def fingerprint_payload
      {
        candidate_id: @candidate_public_id,
        to_stage_code: normalized_value(@transition[:to_stage_code]),
        expected_current_stage_code: normalized_value(@transition[:expected_current_stage_code]),
        reason_code: normalized_value(@transition[:reason_code]),
        note: @transition[:note].to_s.strip.presence,
        evidence: @transition.fetch(:evidence, {}).to_h.deep_stringify_keys.sort.to_h
      }
    end

    def normalized_value(value)
      value.to_s.strip.downcase.presence
    end
  end
end
