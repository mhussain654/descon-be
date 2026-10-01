# frozen_string_literal: true

module AiCalls
  # Backfills candidate_id/candidate_assignment_id onto a CandidateAiCall
  # (and its Communication envelope) once an inbound call that started
  # unidentified successfully verifies -- guarded so a call can never be
  # re-linked to a different candidate after the fact.
  #
  # A call can already be linked to a candidate before verification succeeds
  # -- HandleConversationInitiationService pre-links by caller-ID as a hint
  # when the call is first created. Caller ID is only a hint, never proof:
  # returning success for a pre-linked call without checking whether the
  # *verified* identity actually matches it would let a caller who proves
  # knowledge of a different candidate's reference number + CNIC end up with
  # their call still pointed at the pre-linked (unrelated) candidate --
  # after which every tool would serve that unrelated candidate's data to
  # them. See VerifyCallerIdentity, which treats a mismatch here as a
  # failed verification, not a successful one.
  class LinkVerifiedCandidateService < ApplicationService
    Result = Struct.new(:linked, :mismatch, keyword_init: true)

    def initialize(candidate_ai_call:, candidate:, assignment:)
      @candidate_ai_call = candidate_ai_call
      @candidate = candidate
      @assignment = assignment
    end

    def call
      return Result.new(linked: true) if matches_existing_link?
      return Result.new(linked: false, mismatch: true) if already_linked?

      ActiveRecord::Base.transaction do
        @candidate_ai_call.update!(candidate: @candidate, candidate_assignment: @assignment)
        @candidate_ai_call.communication.update!(candidate_assignment: @assignment)
      end
      Result.new(linked: true)
    end

    private

    def already_linked?
      @candidate_ai_call.candidate_id.present?
    end

    def matches_existing_link?
      already_linked? &&
        @candidate_ai_call.candidate_id == @candidate.id &&
        @candidate_ai_call.candidate_assignment_id == @assignment&.id
    end
  end
end
