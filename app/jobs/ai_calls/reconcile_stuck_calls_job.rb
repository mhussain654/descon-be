# frozen_string_literal: true

module AiCalls
  # Runs every minute (config/recurring.yml) and closes out any
  # CandidateAiCall stuck past its per-status reconciliation threshold (see
  # AiCalls::ReconcileCallService::THRESHOLDS) -- catches calls whose
  # ElevenLabs webhook was evidently missed. RoboCall calls are excluded:
  # they have no webhook, and AiCalls::PollRobocallCallsJob owns them.
  class ReconcileStuckCallsJob < ApplicationJob
    queue_as :default

    def perform
      request_id = SecureRandom.uuid

      CandidateAiCall.non_terminal.where.not(provider_code: 'robocall').find_each do |candidate_ai_call|
        next unless ReconcileCallService.due?(candidate_ai_call)

        ReconcileCallService.new(candidate_ai_call:, request_id:).call
      end
    end
  end
end
