# frozen_string_literal: true

module AiCalls
  # Hands one just-created CandidateAiCall to the configured voice provider
  # and records the provider's call id on it, leaving it `queued`. Split from
  # TriggerOutboundCallService, which owns eligibility, locking and the local
  # records; this owns only the provider wire call. Raises
  # AiCallProviderRequestError when the provider answers without a call id
  # (it could never be looked up again), which rolls the trigger back.
  class ProviderCallInitiator < ApplicationService
    def initialize(call_record:, plan:, configuration:, elevenlabs_adapter: nil, robocall_adapter: nil)
      @call_record = call_record
      @plan = plan
      @configuration = configuration
      @elevenlabs_adapter = elevenlabs_adapter || Providers::ElevenlabsAdapter.new(configuration:)
      @robocall_adapter = robocall_adapter || Providers::RobocallAdapter.new
    end

    def call
      @configuration.robocall? ? initiate_robocall : initiate_elevenlabs_call
    end

    private

    # RoboCall plays a fixed voice: only the voice id and the number are sent.
    # When RoboCall accepts the call but returns no id to follow it by, the call
    # has been placed, so it is recorded (never rolled back, which would invite
    # a second call to the candidate) and sent straight to manual review.
    def initiate_robocall
      result = @robocall_adapter.initiate_call(voice_id: @plan.voice_id,
                                               to_number: @call_record.candidate.mobile_number)
      return hold_untrackable_call if result.call_id.blank?

      @call_record.update!(robocall_call_id: result.call_id, status: 'queued', started_at: Time.current)
    end

    def hold_untrackable_call
      @call_record.update!(
        status: 'completed', outcome: nil, outcome_reason: 'needs_manual_review', started_at: Time.current,
        completed_at: Time.current,
        failure_message: 'RoboCall accepted the call but returned no call id, so its result cannot be tracked'
      )
    end

    def initiate_elevenlabs_call
      prompt = @plan.prompt_source.build(candidate: @call_record.candidate, language_code: @call_record.language_code)
      result = @elevenlabs_adapter.initiate_outbound_call(outbound_call_request(prompt))
      # A 2xx response missing a conversation_id is otherwise indistinguishable
      # from a real one -- without this check the call would be marked
      # 'queued' with no way to ever look it up again (reconciliation's
      # Twilio/ElevenLabs cross-check both key off these ids), leaving it
      # stuck in 'queued' forever, past every reconciliation threshold.
      raise AiCallProviderRequestError if result.conversation_id.blank?

      @call_record.update!(elevenlabs_conversation_id: result.conversation_id, twilio_call_sid: result.twilio_call_sid,
                           status: 'queued')
    end

    def outbound_call_request(prompt)
      Providers::OutboundCallRequest.new(
        agent_id: @call_record.elevenlabs_agent_id,
        agent_phone_number_id: @call_record.elevenlabs_agent_phone_number_id,
        to_number: @call_record.candidate.mobile_number,
        dynamic_variables: prompt.dynamic_variables,
        conversation_config_override: prompt.conversation_config_override,
        recording_enabled: @configuration.recording_enabled?
      )
    end
  end
end
