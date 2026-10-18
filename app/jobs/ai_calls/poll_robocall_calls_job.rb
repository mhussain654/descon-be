# frozen_string_literal: true

module AiCalls
  # Runs every minute (config/recurring.yml). RoboCall has no webhooks, so the
  # result of every call still open is read from its status endpoint here
  # (see AiCalls::PollRobocallCallService).
  class PollRobocallCallsJob < ApplicationJob
    queue_as :default

    def perform
      request_id = SecureRandom.uuid

      CandidateAiCall.non_terminal.where(provider_code: 'robocall').find_each do |candidate_ai_call|
        PollRobocallCallService.new(candidate_ai_call:, request_id:).call
      end
    end
  end
end
