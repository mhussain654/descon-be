# frozen_string_literal: true

module AiCalls
  # Classifies ElevenLabs' conversation lifecycle status for
  # AiCalls::ReconcileCallService, keeping that class focused on Twilio
  # cross-checking and event recording rather than ElevenLabs status
  # vocabulary. See the "ASSUMED SHAPE" note on
  # AiCalls::PostCallWebhookPayload#status -- not yet verified against a
  # real payload.
  #
  # A conversation record existing (a `conversation_id` present) is not by
  # itself proof the call is over -- a queued/active conversation also has
  # one, so the actual status must be classified before treating the call
  # as answered.
  module ElevenlabsConversationStatus
    DONE = 'done'
    FAILED = 'failed'
    OPEN_STATUS_TO_LOCAL_STATUS = {
      'initiated' => 'ringing', 'in-progress' => 'in_progress', 'processing' => 'processing'
    }.freeze

    # :done, :failed, :unknown, or the local CandidateAiCall#status this
    # open ElevenLabs status corresponds to.
    def self.classify(status)
      return :done if status == DONE
      return :failed if status == FAILED
      return OPEN_STATUS_TO_LOCAL_STATUS.fetch(status) if OPEN_STATUS_TO_LOCAL_STATUS.key?(status)

      :unknown
    end
  end
end
