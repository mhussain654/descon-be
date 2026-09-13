# frozen_string_literal: true

module AiCalls
  # Backfills candidate_id/candidate_assignment_id onto a CandidateAiCall
  # (and its Communication envelope) once an inbound call that started
  # unidentified successfully verifies -- guarded so a call can never be
  # re-linked to a different candidate after the fact.
  class LinkVerifiedCandidateService < ApplicationService
    def initialize(candidate_ai_call:, candidate:, assignment:)
      @candidate_ai_call = candidate_ai_call
      @candidate = candidate
      @assignment = assignment
    end

    def call
      return @candidate_ai_call if already_linked?

      ActiveRecord::Base.transaction do
        @candidate_ai_call.update!(candidate: @candidate, candidate_assignment: @assignment)
        @candidate_ai_call.communication.update!(candidate_assignment: @assignment)
      end
      @candidate_ai_call
    end

    private

    def already_linked?
      @candidate_ai_call.candidate_id.present?
    end
  end
end
