# frozen_string_literal: true

module AiCalls
  # Keeps a CandidateAiCall's Communication envelope in sync with the call's
  # own lifecycle -- without this, the central admin communications log
  # (Admin::CommunicationsController) permanently shows whatever status the
  # Communication was created with ('requested' for outbound, 'in_progress'
  # for inbound), no provider reference, and no sent/delivered/failed
  # timestamps, no matter how the call actually finishes. Call after every
  # `candidate_ai_call.update!` that changes status/outcome/failure state,
  # from inside the same transaction (see WebhookEventRecorder/
  # TriggerOutboundCallService, both already transactional).
  #
  # `status_code` mirrors CandidateAiCall#status verbatim -- both share the
  # same lifecycle vocabulary (requested/queued/ringing/in_progress/
  # processing/completed/failed/cancelled), and there is no other channel
  # (SMS/email) live yet whose own status vocabulary this would need to stay
  # compatible with. The milestone timestamps are set once and never
  # cleared/overwritten, since they each represent a specific point the call
  # passed through, not its current state.
  class SyncCommunicationStatusService
    def self.call(candidate_ai_call) = new(candidate_ai_call).call

    def initialize(candidate_ai_call)
      @candidate_ai_call = candidate_ai_call
      @communication = candidate_ai_call.communication
    end

    def call
      @communication.update!(
        status_code: @candidate_ai_call.status,
        provider_reference: provider_reference,
        error_code: @candidate_ai_call.failure_code.presence,
        sent_at: @communication.sent_at || sent_at,
        delivered_at: @communication.delivered_at || @candidate_ai_call.answered_at,
        failed_at: @communication.failed_at || failed_at
      )
    end

    private

    def provider_reference
      (@candidate_ai_call.elevenlabs_conversation_id || @candidate_ai_call.twilio_call_sid).presence ||
        @communication.provider_reference
    end

    # The call has been successfully handed to the provider once it leaves
    # 'requested' (its just-created state) -- the voice-call analogue of "the
    # message was sent to the carrier".
    def sent_at
      return nil if @candidate_ai_call.status == 'requested'

      @candidate_ai_call.started_at || Time.current
    end

    def failed_at
      Time.current if @candidate_ai_call.status == 'failed'
    end
  end
end
